defmodule ShotElixirWeb.Api.V2.UserController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixir.Discord.LinkCodes

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/users
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Authorization: admin or gamemaster for campaign queries
    authorized =
      cond do
        current_user.admin ->
          :admin

        current_user.gamemaster && params["campaign_id"] ->
          case Campaigns.get_campaign(params["campaign_id"]) do
            nil ->
              :forbidden

            campaign ->
              if campaign.user_id == current_user.id do
                :gamemaster
              else
                :forbidden
              end
          end

        true ->
          :forbidden
      end

    case authorized do
      :forbidden ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})

      _ ->
        result = Accounts.list_campaign_users(params, current_user)

        conn
        |> put_view(ShotElixirWeb.Api.V2.UserView)
        |> render("index.json", users: result.users, meta: result.meta)
    end
  end

  # GET /api/v2/users/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    # First check if the user exists
    case Accounts.get_user(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not found"})

      user ->
        # Then check authorization
        if current_user.admin || current_user.id == id do
          # Preload associations for full user data
          # force: true ensures fresh data since get_user already preloaded :image_positions
          user =
            user
            |> ShotElixir.Repo.preload(
              [
                :image_positions,
                :current_campaign,
                :campaigns,
                :player_campaigns
              ],
              force: true
            )

          conn
          |> put_view(ShotElixirWeb.Api.V2.UserView)
          |> render(:show, user: user)
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Forbidden"})
        end
    end
  end

  # GET /api/v2/users/current
  def current(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    if user do
      # Ensure user has onboarding progress
      ShotElixir.Onboarding.ensure_onboarding_progress!(user)

      # Preload associations including characters scoped to current campaign
      user = preload_user_with_characters(user)
      user = ShotElixir.Repo.preload(user, [:onboarding_progress])

      conn
      |> put_view(ShotElixirWeb.Api.V2.UserView)
      |> render("current.json", user: user)
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Not authenticated"})
    end
  end

  # GET /api/v2/users/profile or /api/v2/users/:id/profile
  def profile(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user do
      case params do
        %{"id" => id} ->
          # Accessing a specific user's profile
          if current_user.admin || current_user.id == id do
            case Accounts.get_user(id) do
              nil ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Not found"})

              user ->
                user = preload_user_with_characters(user)

                conn
                |> put_view(ShotElixirWeb.Api.V2.UserView)
                |> render(:profile, user: user)
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Forbidden"})
          end

        _ ->
          # Accessing own profile - always allowed
          user = preload_user_with_characters(current_user)

          conn
          |> put_view(ShotElixirWeb.Api.V2.UserView)
          |> render(:profile, user: user)
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Not authenticated"})
    end
  end

  # POST /api/v2/users - Public registration endpoint
  def create(conn, user_params) do
    # Handle JSON string parsing like Rails
    parsed_params =
      case user_params do
        %{"user" => user_data} when is_binary(user_data) ->
          case Jason.decode(user_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid user data format"})
              |> halt()
          end

        %{"user" => user_data} when is_map(user_data) ->
          user_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "User parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      case Accounts.create_user(parsed_params) do
        {:ok, user} ->
          # Generate and persist confirmation token
          {:ok, user} = Accounts.generate_confirmation_token(user)

          # Queue confirmation email
          %{
            "type" => "confirmation_instructions",
            "user_id" => user.id,
            "token" => user.confirmation_token
          }
          |> ShotElixir.Workers.EmailWorker.new()
          |> Oban.insert()

          # Handle image upload if present
          case conn.params["image"] do
            %Plug.Upload{} = upload ->
              # Upload image to ImageKit
              case ShotElixir.Services.ImagekitService.upload_plug(upload) do
                {:ok, upload_result} ->
                  # Attach image to user via ActiveStorage
                  case ShotElixir.ActiveStorage.attach_image("User", user.id, upload_result) do
                    {:ok, _attachment} ->
                      # Reload user to get fresh data after image attachment
                      # force: true ensures fresh data since get_user already preloaded :image_positions
                      user =
                        Accounts.get_user(user.id)
                        |> ShotElixir.Repo.preload(
                          [
                            :image_positions,
                            :current_campaign,
                            :campaigns,
                            :player_campaigns
                          ],
                          force: true
                        )

                      {:ok, token, _claims} = Guardian.encode_and_sign(user)

                      conn
                      |> put_status(:created)
                      |> put_resp_header("authorization", "Bearer #{token}")
                      |> put_view(ShotElixirWeb.Api.V2.UserView)
                      |> render(:show, user: user, token: token)

                    {:error, changeset} ->
                      conn
                      |> put_status(:unprocessable_entity)
                      |> put_view(ShotElixirWeb.Api.V2.UserView)
                      |> render(:error, changeset: changeset)
                  end

                {:error, reason} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Image upload failed: #{inspect(reason)}"})
              end

            _ ->
              # No image uploaded, proceed normally
              {:ok, token, _claims} = Guardian.encode_and_sign(user)

              conn
              |> put_status(:created)
              |> put_resp_header("authorization", "Bearer #{token}")
              |> put_view(ShotElixirWeb.Api.V2.UserView)
              |> render(:show, user: user, token: token)
          end

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.UserView)
          |> render(:error, changeset: changeset)
      end
    end
  end

  # POST /api/v2/users/register (public endpoint)
  def register(conn, user_params) do
    # Handle JSON string parsing like Rails
    parsed_params =
      case user_params do
        %{"user" => user_data} when is_binary(user_data) ->
          case Jason.decode(user_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid user data format"})
              |> halt()
          end

        %{"user" => user_data} when is_map(user_data) ->
          user_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "User parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      # The gamemaster flag is a self-selected role, not a security privilege.
      # Gamemasters run campaigns and see onboarding milestones; players join campaigns.
      # Both roles have equal system access - this only affects UX flow.
      # Default to player (gamemaster: false) unless explicitly set.
      final_params =
        Map.put(parsed_params, "gamemaster", Map.get(parsed_params, "gamemaster", false))

      case Accounts.create_user(final_params) do
        {:ok, user} ->
          # Generate and persist confirmation token
          {:ok, user} = Accounts.generate_confirmation_token(user)

          # Queue confirmation email
          %{
            "type" => "confirmation_instructions",
            "user_id" => user.id,
            "token" => user.confirmation_token
          }
          |> ShotElixir.Workers.EmailWorker.new()
          |> Oban.insert()

          {:ok, token, claims} = Guardian.encode_and_sign(user)

          conn
          |> put_status(:created)
          |> put_resp_header("authorization", "Bearer #{token}")
          |> json(%{
            code: 201,
            message: "Registration successful. Please check your email to confirm your account.",
            data: render_user_data(user),
            payload: claims
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.UserView)
          |> render(:error, changeset: changeset)
      end
    end
  end

  # PATCH/PUT /api/v2/users/:id
  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Accounts.get_user(params["id"]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Record not found"})

      user ->
        # Check authorization - only admin or self can update
        if current_user.admin || current_user.id == user.id do
          # Handle image upload if present
          case conn.params["image"] do
            %Plug.Upload{} = upload ->
              # Upload image to ImageKit
              case ShotElixir.Services.ImagekitService.upload_plug(upload) do
                {:ok, upload_result} ->
                  # Attach image to user via ActiveStorage
                  case ShotElixir.ActiveStorage.attach_image("User", user.id, upload_result) do
                    {:ok, _attachment} ->
                      # Reload user to get fresh data after image attachment
                      user = Accounts.get_user(user.id)
                      # Continue with user update
                      update_user_with_params(conn, user, params)

                    {:error, changeset} ->
                      conn
                      |> put_status(:unprocessable_entity)
                      |> put_view(ShotElixirWeb.Api.V2.UserView)
                      |> render(:error, changeset: changeset)
                  end

                {:error, reason} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Image upload failed: #{inspect(reason)}"})
              end

            _ ->
              # No image uploaded, proceed with normal update
              update_user_with_params(conn, user, params)
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Forbidden"})
        end
    end
  end

  # PATCH /api/v2/users/profile
  def update_profile(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Handle JSON string parsing like Rails
    parsed_params =
      case params do
        %{"user" => user_data} when is_binary(user_data) ->
          case Jason.decode(user_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid user data format"})
              |> halt()
          end

        %{"user" => user_data} when is_map(user_data) ->
          user_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "User parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      # Handle image upload if present
      case conn.params["image"] do
        %Plug.Upload{} = upload ->
          # Upload image to ImageKit
          case ShotElixir.Services.ImagekitService.upload_plug(upload) do
            {:ok, upload_result} ->
              # Attach image to user via ActiveStorage
              case ShotElixir.ActiveStorage.attach_image("User", current_user.id, upload_result) do
                {:ok, _attachment} ->
                  # Reload user to get fresh data after image attachment
                  current_user = Accounts.get_user(current_user.id)
                  # Continue with user update
                  case Accounts.update_user(current_user, parsed_params) do
                    {:ok, updated_user} ->
                      # update_user now returns user with preloaded associations via broadcast_user_update
                      {:ok, token, _claims} = Guardian.encode_and_sign(updated_user)

                      conn
                      |> put_resp_header("authorization", "Bearer #{token}")
                      |> put_view(ShotElixirWeb.Api.V2.UserView)
                      |> render(:show, user: updated_user)

                    {:error, changeset} ->
                      conn
                      |> put_status(:unprocessable_entity)
                      |> put_view(ShotElixirWeb.Api.V2.UserView)
                      |> render(:error, changeset: changeset)
                  end

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.UserView)
                  |> render(:error, changeset: changeset)
              end

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Image upload failed: #{inspect(reason)}"})
          end

        _ ->
          # No image uploaded, proceed with normal update
          case Accounts.update_user(current_user, parsed_params) do
            {:ok, updated_user} ->
              # update_user now returns user with preloaded associations via broadcast_user_update
              {:ok, token, _claims} = Guardian.encode_and_sign(updated_user)

              conn
              |> put_resp_header("authorization", "Bearer #{token}")
              |> put_view(ShotElixirWeb.Api.V2.UserView)
              |> render(:show, user: updated_user)

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> put_view(ShotElixirWeb.Api.V2.UserView)
              |> render(:error, changeset: changeset)
          end
      end
    end
  end

  # POST /api/v2/users/change_password
  def change_password(conn, %{
        "current_password" => current_password,
        "password" => password,
        "password_confirmation" => password_confirmation
      }) do
    current_user = Guardian.Plug.current_resource(conn)

    # Verify password confirmation matches
    if password != password_confirmation do
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{success: false, errors: %{password_confirmation: ["does not match password"]}})
    else
      case Accounts.change_password(current_user, current_password, password) do
        {:ok, _user} ->
          conn
          |> json(%{success: true, message: "Password changed successfully"})

        {:error, :invalid_current_password} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{success: false, errors: %{current_password: ["is incorrect"]}})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.UserView)
          |> render(:error, changeset: changeset)
      end
    end
  end

  def change_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "current_password, password, and password_confirmation are required"})
  end

  # DELETE /api/v2/users/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Admin can delete any user, users can delete themselves
    unless current_user.admin || current_user.id == id do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden"})
    else
      case Accounts.get_user(id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Record not found"})

        user ->
          {:ok, _user} = Accounts.delete_user(user)
          send_resp(conn, :no_content, "")
      end
    end
  end

  # POST /api/v2/users/link_discord
  def link_discord(conn, %{"code" => code}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Use atomic validate_and_consume to prevent race conditions
    # The code is consumed regardless of outcome to prevent enumeration attacks
    case LinkCodes.validate_and_consume(code) do
      {:error, :invalid_code} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid link code"})

      {:error, :expired} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Link code has expired"})

      {:ok, %{discord_id: discord_id, discord_username: discord_username}} ->
        # Check if current user is already linked to a different Discord account
        if current_user.discord_id && current_user.discord_id != discord_id do
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            error:
              "You are already linked to a different Discord account. Please unlink before linking a new one."
          })
        else
          # Check if Discord ID is already linked to another user
          case Accounts.get_user_by_discord_id(discord_id) do
            nil ->
              # Link the Discord account (store username for future email notifications)
              case Accounts.link_discord(current_user, discord_id, discord_username) do
                {:ok, _updated_user} ->
                  # Queue discord_linked email
                  %{
                    "type" => "discord_linked",
                    "user_id" => current_user.id,
                    "discord_username" => discord_username
                  }
                  |> ShotElixir.Workers.EmailWorker.new()
                  |> Oban.insert()

                  conn
                  |> json(%{
                    success: true,
                    message: "Discord account linked successfully",
                    discord_username: discord_username
                  })

                {:error, _changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to link Discord account"})
              end

            existing_user ->
              if existing_user.id == current_user.id do
                # Already linked to this user
                conn
                |> json(%{
                  success: true,
                  message: "Discord account already linked",
                  discord_username: discord_username
                })
              else
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "This Discord account is already linked to another user"})
              end
          end
        end
    end
  end

  def link_discord(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Code parameter is required"})
  end

  # DELETE /api/v2/users/unlink_discord
  def unlink_discord(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.discord_id do
      # Capture discord info before unlinking for the email
      discord_username = current_user.discord_username || "ID: #{current_user.discord_id}"

      case Accounts.unlink_discord(current_user) do
        {:ok, _updated_user} ->
          # Queue discord_unlinked email
          %{
            "type" => "discord_unlinked",
            "user_id" => current_user.id,
            "discord_username" => discord_username
          }
          |> ShotElixir.Workers.EmailWorker.new()
          |> Oban.insert()

          conn
          |> json(%{
            success: true,
            message: "Discord account unlinked successfully"
          })

        {:error, _changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "Failed to unlink Discord account"})
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No Discord account is linked"})
    end
  end

  # DELETE /api/v2/users/:id/remove_image
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Accounts.get_user(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Record not found"})

      user ->
        # Only admin or self can remove image
        if current_user.admin || current_user.id == user.id do
          # Remove image via ActiveStorage
          case ShotElixir.ActiveStorage.delete_image("User", user.id) do
            {:ok, _} ->
              # Reload user to get fresh data after image removal
              # force: true ensures fresh data since get_user already preloaded :image_positions
              user =
                Accounts.get_user(user.id)
                |> ShotElixir.Repo.preload(
                  [
                    :image_positions,
                    :current_campaign,
                    :campaigns,
                    :player_campaigns
                  ],
                  force: true
                )

              {:ok, token, _claims} = Guardian.encode_and_sign(user)

              conn
              |> put_resp_header("authorization", "Bearer #{token}")
              |> put_view(ShotElixirWeb.Api.V2.UserView)
              |> render(:show, user: user)

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> put_view(ShotElixirWeb.Api.V2.UserView)
              |> render(:error, changeset: changeset)
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Admin access required to remove another user's image"})
        end
    end
  end

  # Helper function for handling user update with potential image upload
  defp update_user_with_params(conn, user, params) do
    # Handle JSON string parsing like Rails
    parsed_params =
      case params do
        %{"user" => user_data} when is_binary(user_data) ->
          case Jason.decode(user_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid user data format"})
              |> halt()
          end

        %{"user" => user_data} when is_map(user_data) ->
          user_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "User parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      case Accounts.update_user(user, parsed_params) do
        {:ok, updated_user} ->
          # update_user now returns user with preloaded associations via broadcast_user_update
          {:ok, token, _claims} = Guardian.encode_and_sign(updated_user)

          conn
          |> put_resp_header("authorization", "Bearer #{token}")
          |> put_view(ShotElixirWeb.Api.V2.UserView)
          |> render(:show, user: updated_user)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.UserView)
          |> render(:error, changeset: changeset)
      end
    end
  end

  # Helper function for rendering user data in register response
  defp render_user_data(user) do
    %{
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      name: user.name,
      admin: user.admin,
      gamemaster: user.gamemaster,
      active: user.active,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  # Helper function to preload user with characters scoped to current campaign
  defp preload_user_with_characters(user) do
    import Ecto.Query
    require Logger

    Logger.debug("preload_user_with_characters called for user #{user.id}")
    Logger.debug("current_campaign_id: #{inspect(user.current_campaign_id)}")

    # Base preloads
    user =
      user
      |> ShotElixir.Repo.preload([
        :current_campaign,
        :campaigns,
        :player_campaigns,
        :image_positions
      ])

    # Preload characters scoped to current campaign if one is set
    case user.current_campaign_id do
      nil ->
        Logger.debug("No current campaign, returning empty characters")
        # No current campaign, return empty characters
        Map.put(user, :characters, [])

      campaign_id ->
        # Preload characters filtered by current campaign
        characters_query =
          from c in ShotElixir.Characters.Character,
            where: c.user_id == ^user.id and c.campaign_id == ^campaign_id,
            order_by: [asc: c.name]

        characters = ShotElixir.Repo.all(characters_query)
        Logger.debug("Found #{length(characters)} characters for campaign #{campaign_id}")
        Map.put(user, :characters, characters)
    end
  end
end
