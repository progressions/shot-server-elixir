defmodule ShotElixirWeb.Api.V2.InvitationController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Invitations
  alias ShotElixir.Campaigns
  alias ShotElixir.Accounts
  alias ShotElixir.Guardian
  alias ShotElixir.Workers.EmailWorker

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/invitations
  # Returns pending invitations for current campaign
  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      # Verify user has access to campaign and is gamemaster
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_gamemaster_access(campaign, current_user) do
            invitations = Invitations.list_campaign_invitations(current_user.current_campaign_id)
            render(conn, :index, invitations: invitations)
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Unauthorized"})
          end
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # POST /api/v2/invitations
  # Creates new invitation and sends email
  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Rate limiting check
    # Rate limiting always returns :ok for now
    :ok = Invitations.check_invitation_rate_limit(current_user.id)

    if current_user.current_campaign_id do
      # Verify user has access to campaign and is gamemaster
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "No active campaign selected"})

        campaign ->
          if authorize_gamemaster_access(campaign, current_user) do
            invitation_params =
              Map.merge(
                params["invitation"] || %{},
                %{
                  "user_id" => current_user.id,
                  "campaign_id" => current_user.current_campaign_id
                }
              )

            case Invitations.create_invitation(invitation_params) do
              {:ok, invitation} ->
                # Queue invitation email for delivery
                %{"type" => "invitation", "invitation_id" => invitation.id}
                |> EmailWorker.new()
                |> Oban.insert()

                conn
                |> put_status(:created)
                |> render(:show, invitation: invitation)
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Unauthorized"})
          end
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # POST /api/v2/invitations/:id/resend
  # Resends invitation email
  def resend(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Rate limiting check
    # Rate limiting always returns :ok for now
    :ok = Invitations.check_invitation_rate_limit(current_user.id)

    if current_user.current_campaign_id do
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_gamemaster_access(campaign, current_user) do
            case Invitations.get_invitation(id) do
              nil ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Invitation not found"})

              invitation ->
                if invitation.campaign_id == current_user.current_campaign_id do
                  # Queue invitation email for delivery
                  %{"type" => "invitation", "invitation_id" => invitation.id}
                  |> EmailWorker.new()
                  |> Oban.insert()

                  render(conn, :show, invitation: invitation)
                else
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Invitation not found"})
                end
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Unauthorized"})
          end
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/invitations/:id
  # Returns invitation details (public endpoint for redemption page)
  def show(conn, %{"id" => id}) do
    case Invitations.get_invitation(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invitation not found"})

      invitation ->
        render(conn, :show, invitation: invitation)
    end
  end

  # POST /api/v2/invitations/:id/redeem
  # Redeems invitation and adds user to campaign
  def redeem(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Invitations.get_invitation(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invitation not found"})

      invitation ->
        # Check if invitation email matches current user
        if current_user.email != invitation.email do
          conn
          |> put_status(:forbidden)
          |> render("mismatch.json", %{
            error: "This invitation is for #{invitation.email}",
            current_user_email: current_user.email,
            invitation_email: invitation.email
          })
        else
          case Invitations.redeem_invitation(invitation, current_user.id) do
            {:ok, campaign} ->
              # TODO: Broadcast update for real-time UI updates
              # BroadcastCampaignUpdateJob.perform_later("Campaign", campaign.id)
              conn
              |> put_status(:created)
              |> render("redeem.json", %{
                campaign: campaign,
                message: "Successfully joined #{campaign.name}!"
              })

            {:error, :already_member} ->
              campaign = Campaigns.get_campaign(invitation.campaign_id)

              conn
              |> put_status(:conflict)
              |> render("already_member.json", %{
                error: "Already a member of this campaign",
                campaign: campaign
              })

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> render(:error, changeset: changeset)
          end
        end
    end
  end

  # POST /api/v2/invitations/:id/register
  # Creates new user account for invitation email
  def register(conn, %{"id" => id} = params) do
    ip_address = get_client_ip(conn)

    case Invitations.get_invitation(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Invitation not found"})

      invitation ->
        # Rate limiting check
        # Rate limiting always returns :ok for now
        :ok = Invitations.check_registration_rate_limit(ip_address, invitation.email)
        # Only allow registration for invitations without existing users
        if invitation.pending_user do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error: "User already exists for this email address",
            has_account: true
          })
        else
          # Validate email matches invitation
          if params["email"] && params["email"] != invitation.email do
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              error: "Email must match invitation email",
              invitation_email: invitation.email
            })
          else
            # Additional security validations
            cond do
              not Invitations.valid_email_format?(invitation.email) ->
                conn
                |> put_status(:unprocessable_entity)
                |> render("error.json", %{
                  error: "Invalid email format",
                  field: "email"
                })

              not Invitations.valid_password?(params["password"]) ->
                conn
                |> put_status(:unprocessable_entity)
                |> render("error.json", %{
                  error:
                    "Password must be at least 8 characters long and contain letters and numbers",
                  field: "password"
                })

              true ->
                # Create new user
                user_attrs = %{
                  "email" => invitation.email,
                  "first_name" => Invitations.sanitize_name_field(params["first_name"]),
                  "last_name" => Invitations.sanitize_name_field(params["last_name"]),
                  "password" => params["password"],
                  "password_confirmation" => params["password_confirmation"],
                  "pending_invitation_id" => invitation.id
                }

                case Accounts.create_user(user_attrs) do
                  {:ok, user} ->
                    # TODO: Implement email confirmation system
                    # Generate confirmation token and send confirmation_instructions email
                    # For now, user accounts are created without email confirmation
                    # %{"type" => "confirmation_instructions", "user_id" => user.id, "token" => token}
                    # |> EmailWorker.new()
                    # |> Oban.insert()

                    conn
                    |> put_status(:created)
                    |> render("register.json", %{
                      message:
                        "Account created! Check #{invitation.email} for confirmation email.",
                      requires_confirmation: true,
                      user: user
                    })

                  {:error, changeset} ->
                    conn
                    |> put_status(:unprocessable_entity)
                    |> render(:error, changeset: changeset)
                end
            end
          end
        end
    end
  end

  # DELETE /api/v2/invitations/:id
  # Cancels pending invitation
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_gamemaster_access(campaign, current_user) do
            case Invitations.get_invitation(id) do
              nil ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Invitation not found"})

              invitation ->
                if invitation.campaign_id == current_user.current_campaign_id do
                  case Invitations.delete_invitation(invitation) do
                    {:ok, _} ->
                      send_resp(conn, :no_content, "")

                    {:error, _} ->
                      conn
                      |> put_status(:unprocessable_entity)
                      |> json(%{error: "Failed to delete invitation"})
                  end
                else
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Invitation not found"})
                end
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Unauthorized"})
          end
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # Private helper functions
  defp authorize_gamemaster_access(campaign, user) do
    user.gamemaster || campaign.user_id == user.id
  end

  defp get_client_ip(conn) do
    case Plug.Conn.get_req_header(conn, "x-forwarded-for") do
      [ip | _] -> ip |> String.split(",") |> hd() |> String.trim()
      [] -> to_string(:inet_parse.ntoa(conn.remote_ip))
    end
  end
end
