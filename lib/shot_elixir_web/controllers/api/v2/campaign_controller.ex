defmodule ShotElixirWeb.Api.V2.CampaignController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Guardian
  alias ShotElixir.Services.BatchImageGenerationService

  action_fallback ShotElixirWeb.FallbackController

  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    campaigns = Campaigns.list_user_campaigns(current_user.id, params, current_user)

    conn
    |> put_view(ShotElixirWeb.Api.V2.CampaignView)
    |> render("index.json", campaigns: campaigns.campaigns, meta: campaigns.meta)
  end

  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    campaign =
      if id == "current" do
        # Get current campaign from user
        current_user.current_campaign_id &&
          Campaigns.get_campaign(current_user.current_campaign_id)
      else
        Campaigns.get_campaign(id)
      end

    with %Campaign{} = campaign <- campaign,
         :ok <- authorize_campaign_access(campaign, current_user) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.CampaignView)
      |> render("show.json", campaign: campaign)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def create(conn, %{"campaign" => campaign_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with :ok <- authorize_gamemaster_or_admin(current_user) do
      # Handle JSON string parameters for Rails compatibility
      parsed_params = parse_json_params(campaign_params)

      params = Map.put(parsed_params, "user_id", current_user.id)

      case Campaigns.create_campaign(params) do
        {:ok, campaign} ->
          conn
          |> put_status(:created)
          |> put_view(ShotElixirWeb.Api.V2.CampaignView)
          |> render("show.json", campaign: campaign)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.CampaignView)
          |> render("error.json", changeset: changeset)
      end
    else
      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
    end
  end

  def update(conn, %{"id" => id, "campaign" => campaign_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with :ok <- authorize_gamemaster_or_admin(current_user),
         %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user) do
      # Handle JSON string parameters for Rails compatibility
      parsed_params = parse_json_params(campaign_params)

      case Campaigns.update_campaign(campaign, parsed_params) do
        {:ok, updated_campaign} ->
          conn
          |> put_view(ShotElixirWeb.Api.V2.CampaignView)
          |> render("show.json", campaign: updated_campaign)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.CampaignView)
          |> render("error.json", changeset: changeset)
      end
    else
      nil ->
        {:error, :not_found}

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with :ok <- authorize_gamemaster_or_admin(current_user),
         %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user) do
      # Check if trying to delete current campaign
      if campaign.id == current_user.current_campaign_id do
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Cannot destroy the current campaign"})
      else
        case Campaigns.delete_campaign(campaign) do
          {:ok, _} -> send_resp(conn, :no_content, "")
          {:error, reason} -> {:error, reason}
        end
      end
    else
      nil ->
        {:error, :not_found}

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  def current(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    case current_user.current_campaign_id do
      nil ->
        conn |> json(nil)

      campaign_id ->
        case Campaigns.get_campaign(campaign_id) do
          %Campaign{} = campaign ->
            # Return campaign directly for Rails compatibility
            # Call the view render function and send as JSON directly
            view_module = ShotElixirWeb.Api.V2.CampaignView
            campaign_data = view_module.render("current.json", %{campaign: campaign})
            conn |> json(campaign_data)

          nil ->
            conn |> json(nil)
        end
    end
  end

  # Custom endpoints
  def set(conn, params) do
    id = params["campaign_id"] || params["id"]
    current_user = Guardian.Plug.current_resource(conn)

    cond do
      is_nil(id) ->
        with {:ok, _user} <- ShotElixir.Accounts.set_current_campaign(current_user, nil) do
          conn |> json(nil)
        else
          {:error, reason} -> {:error, reason}
        end

      true ->
        with %Campaign{} = campaign <- Campaigns.get_campaign(id),
             :ok <- authorize_campaign_access(campaign, current_user),
             {:ok, updated_user} <-
               ShotElixir.Accounts.set_current_campaign(current_user, campaign.id) do
          conn
          |> put_view(ShotElixirWeb.Api.V2.CampaignView)
          |> render("set_current.json", campaign: campaign, user: updated_user)
        else
          nil -> {:error, :not_found}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  def set_current(conn, %{"campaign_id" => campaign_id}) do
    set(conn, %{"id" => campaign_id})
  end

  def current_fight(conn, %{"campaign_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_access(campaign, current_user) do
      # Get the most recent ongoing fight for the campaign
      # Filter for fights that are started but not ended (ongoing)
      fights = ShotElixir.Fights.list_fights(campaign.id)

      current_fight =
        fights
        |> Enum.filter(fn fight ->
          fight.started_at != nil && fight.ended_at == nil
        end)
        |> List.first()

      # Preload necessary associations for the fight if it exists
      current_fight_with_associations =
        if current_fight do
          ShotElixir.Repo.preload(current_fight, [:characters, :vehicles, :image_positions])
        else
          nil
        end

      conn
      |> put_view(ShotElixirWeb.Api.V2.CampaignView)
      |> render("current_fight.json",
        fight: current_fight_with_associations
      )
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Campaign not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to view this campaign"})
    end
  end

  # Membership management
  def add_member(conn, %{"campaign_id" => id, "user_id" => user_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user),
         %ShotElixir.Accounts.User{} = user <- ShotElixir.Accounts.get_user(user_id),
         {:ok, membership} <- Campaigns.add_member(campaign, user) do
      # Queue joined campaign email
      %{
        "type" => "joined_campaign",
        "user_id" => user.id,
        "campaign_id" => campaign.id
      }
      |> ShotElixir.Workers.EmailWorker.new()
      |> Oban.insert()

      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.CampaignView)
      |> render("membership.json", membership: membership)
    else
      nil ->
        {:error, :not_found}

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.CampaignView)
        |> render("error.json", changeset: changeset)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def remove_member(conn, %{"campaign_id" => id, "user_id" => user_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user),
         %ShotElixir.Accounts.User{} = user <- ShotElixir.Accounts.get_user(user_id),
         {_count, _} <- Campaigns.remove_member(campaign, user) do
      # Queue removed from campaign email
      %{
        "type" => "removed_from_campaign",
        "user_id" => user.id,
        "campaign_id" => campaign.id
      }
      |> ShotElixir.Workers.EmailWorker.new()
      |> Oban.insert()

      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Starts batch image generation for all entities in a campaign that don't have images.
  Gamemaster only.
  """
  def generate_batch_images(conn, %{"campaign_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user),
         {:ok, total} <- BatchImageGenerationService.start_batch_generation(id) do
      conn
      |> put_status(:accepted)
      |> json(%{
        message: "Batch image generation started",
        total_entities: total,
        campaign_id: id
      })
    else
      nil ->
        {:error, :not_found}

      {:error, :campaign_not_found} ->
        {:error, :not_found}

      {:error, {:already_in_progress, status}} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Batch operation already in progress", status: status})

      {:error, :no_entities_without_images} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "All entities already have images", total_entities: 0})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Resets the Grok credit exhaustion status for a campaign.
  Also clears any stuck batch image generation status.
  Gamemaster only.
  """
  def reset_grok_credits(conn, %{"campaign_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user),
         {:ok, updated_campaign} <-
           Campaigns.update_campaign(campaign, %{
             grok_credits_exhausted_at: nil,
             batch_image_status: nil,
             batch_images_completed: 0,
             batch_images_total: 0
           }) do
      # Build broadcast payload
      broadcast_payload =
        {:campaign_broadcast,
         %{
           campaign: %{
             id: updated_campaign.id,
             is_grok_credits_exhausted: false,
             grok_credits_exhausted_at: nil,
             is_batch_images_in_progress: false,
             batch_image_status: nil,
             batch_images_completed: 0,
             batch_images_total: 0
           }
         }}

      # Broadcast to campaign channel
      Phoenix.PubSub.broadcast!(
        ShotElixir.PubSub,
        "campaign:#{updated_campaign.id}",
        broadcast_payload
      )

      # Also broadcast to user channel if campaign has an owner
      if updated_campaign.user_id do
        Phoenix.PubSub.broadcast!(
          ShotElixir.PubSub,
          "user:#{updated_campaign.user_id}",
          broadcast_payload
        )
      end

      conn
      |> put_view(ShotElixirWeb.Api.V2.CampaignView)
      |> render("show.json", campaign: updated_campaign)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Campaign not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to reset credits", details: inspect(changeset)})
    end
  end

  # Authorization helpers
  defp authorize_campaign_access(campaign, user) do
    cond do
      campaign.user_id == user.id -> :ok
      user.admin -> :ok
      member_of_campaign?(campaign, user) -> :ok
      true -> {:error, :forbidden}
    end
  end

  defp authorize_campaign_owner(campaign, user) do
    cond do
      campaign.user_id == user.id -> :ok
      user.admin -> :ok
      true -> {:error, :forbidden}
    end
  end

  defp authorize_gamemaster_or_admin(user) do
    if user.gamemaster || user.admin do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp member_of_campaign?(campaign, user) do
    campaigns = Campaigns.get_user_campaigns(user.id)
    Enum.any?(campaigns, fn c -> c.id == campaign.id end)
  end

  # Handle JSON string parameters for Rails compatibility
  defp parse_json_params(params) when is_binary(params) do
    case Jason.decode(params) do
      {:ok, decoded} -> decoded
      {:error, _} -> params
    end
  end

  defp parse_json_params(params), do: params
end
