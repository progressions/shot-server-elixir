defmodule ShotElixirWeb.Api.V2.CampaignController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Guardian.Plug, as: GuardianPlug

  action_fallback ShotElixirWeb.FallbackController

  def index(conn, _params) do
    current_user = GuardianPlug.current_resource(conn)
    campaigns = Campaigns.get_user_campaigns(current_user.id)

    conn
    |> put_view(ShotElixirWeb.Api.V2.CampaignView)
    |> render("index.json", campaigns: campaigns)
  end

  def show(conn, %{"id" => id}) do
    current_user = GuardianPlug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
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
    current_user = GuardianPlug.current_resource(conn)

    params = Map.put(campaign_params, "user_id", current_user.id)

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
  end

  def update(conn, %{"id" => id, "campaign" => campaign_params}) do
    current_user = GuardianPlug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user),
         {:ok, updated_campaign} <- Campaigns.update_campaign(campaign, campaign_params) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.CampaignView)
      |> render("show.json", campaign: updated_campaign)
    else
      nil -> {:error, :not_found}
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.CampaignView)
        |> render("error.json", changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    current_user = GuardianPlug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user),
         {:ok, _} <- Campaigns.delete_campaign(campaign) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Custom endpoints
  def set(conn, params) do
    id = params["campaign_id"] || params["id"]
    current_user = GuardianPlug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_access(campaign, current_user),
         {:ok, updated_user} <- ShotElixir.Accounts.set_current_campaign(current_user, campaign.id) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.CampaignView)
      |> render("set_current.json", campaign: campaign, user: updated_user)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def set_current(conn, %{"campaign_id" => campaign_id}) do
    set(conn, %{"id" => campaign_id})
  end

  def current_fight(conn, %{"campaign_id" => id}) do
    with %Campaign{} = campaign <- Campaigns.get_campaign(id) do
      # Get the most recent active fight for the campaign
      fights = ShotElixir.Fights.list_fights(campaign.id)
      current_fight = List.first(fights)

      conn
      |> put_view(ShotElixirWeb.Api.V2.CampaignView)
      |> render("current_fight.json", campaign: campaign, fight: current_fight)
    else
      nil -> {:error, :not_found}
    end
  end

  # Membership management
  def add_member(conn, %{"campaign_id" => id, "user_id" => user_id}) do
    current_user = GuardianPlug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user),
         %ShotElixir.Accounts.User{} = user <- ShotElixir.Accounts.get_user(user_id),
         {:ok, membership} <- Campaigns.add_member(campaign, user) do
      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.CampaignView)
      |> render("membership.json", membership: membership)
    else
      nil -> {:error, :not_found}
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.CampaignView)
        |> render("error.json", changeset: changeset)
      {:error, reason} -> {:error, reason}
    end
  end

  def remove_member(conn, %{"campaign_id" => id, "user_id" => user_id}) do
    current_user = GuardianPlug.current_resource(conn)

    with %Campaign{} = campaign <- Campaigns.get_campaign(id),
         :ok <- authorize_campaign_owner(campaign, current_user),
         %ShotElixir.Accounts.User{} = user <- ShotElixir.Accounts.get_user(user_id),
         {_count, _} <- Campaigns.remove_member(campaign, user) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Authorization helpers
  defp authorize_campaign_access(campaign, user) do
    cond do
      campaign.user_id == user.id -> :ok
      member_of_campaign?(campaign, user) -> :ok
      true -> {:error, :forbidden}
    end
  end

  defp authorize_campaign_owner(campaign, user) do
    if campaign.user_id == user.id do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp member_of_campaign?(campaign, user) do
    campaigns = Campaigns.get_user_campaigns(user.id)
    Enum.any?(campaigns, fn c -> c.id == campaign.id end)
  end
end