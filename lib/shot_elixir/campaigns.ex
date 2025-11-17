defmodule ShotElixir.Campaigns do
  @moduledoc """
  The Campaigns context.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Campaigns.CampaignMembership
  alias ShotElixir.ImageLoader
  use ShotElixir.Models.Broadcastable

  def list_campaigns do
    Repo.all(Campaign)
  end

  def get_campaign!(id) do
    Repo.get!(Campaign, id)
    |> Repo.preload(:user)
    |> ImageLoader.load_image_url("Campaign")
  end

  def get_campaign(id) do
    Repo.get(Campaign, id)
    |> Repo.preload(:user)
    |> ImageLoader.load_image_url("Campaign")
  end

  def get_user_campaigns(user_id) do
    query =
      from c in Campaign,
        left_join: cm in CampaignMembership,
        on: cm.campaign_id == c.id,
        where: c.user_id == ^user_id or cm.user_id == ^user_id,
        distinct: true

    Repo.all(query)
  end

  @doc """
  Check if a user is a member of a campaign.
  """
  def is_campaign_member?(campaign_id, user_id) do
    from(cm in CampaignMembership,
      where: cm.campaign_id == ^campaign_id and cm.user_id == ^user_id
    )
    |> Repo.exists?()
  end

  def list_user_campaigns(user_id, params \\ %{}, _current_user \\ nil) do
    # Get pagination parameters - handle both string and integer params
    per_page =
      case params["per_page"] do
        nil -> 15
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
      end

    page =
      case params["page"] do
        nil -> 1
        value when is_integer(value) -> value
        value when is_binary(value) -> String.to_integer(value)
      end

    offset = (page - 1) * per_page

    # Base query for user's campaigns (both owned and member)
    query =
      from c in Campaign,
        left_join: cm in CampaignMembership,
        on: cm.campaign_id == c.id,
        where: (c.user_id == ^user_id or cm.user_id == ^user_id) and c.active == true,
        group_by: c.id

    # Apply basic filters
    query =
      if params["id"] do
        from c in query, where: c.id == ^params["id"]
      else
        query
      end

    query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from c in query, where: c.id in ^ids
      else
        query
      end

    query =
      if params["search"] do
        from c in query, where: ilike(c.name, ^"%#{params["search"]}%")
      else
        query
      end

    # Association-based filters
    query =
      if params["character_id"] && params["character_id"] != "" do
        from c in query,
          join: ch in "characters",
          on: ch.campaign_id == c.id,
          where: ch.id == ^params["character_id"]
      else
        query
      end

    query =
      if params["vehicle_id"] && params["vehicle_id"] != "" do
        from c in query,
          join: v in "vehicles",
          on: v.campaign_id == c.id,
          where: v.id == ^params["vehicle_id"]
      else
        query
      end

    # Apply visibility filtering (default to active only)
    query = apply_visibility_filter(query, params)

    # Apply sorting
    query = apply_sorting(query, params)

    # Get total count for pagination (separate query without group_by)
    count_query =
      from c in Campaign,
        left_join: cm in CampaignMembership,
        on: cm.campaign_id == c.id,
        where: (c.user_id == ^user_id or cm.user_id == ^user_id) and c.active == true,
        distinct: c.id

    # Apply same filters to count query
    count_query =
      if params["id"] do
        from c in count_query, where: c.id == ^params["id"]
      else
        count_query
      end

    count_query =
      if params["ids"] do
        ids = parse_ids(params["ids"])
        from c in count_query, where: c.id in ^ids
      else
        count_query
      end

    count_query =
      if params["search"] do
        from c in count_query, where: ilike(c.name, ^"%#{params["search"]}%")
      else
        count_query
      end

    count_query =
      if params["character_id"] && params["character_id"] != "" do
        from c in count_query,
          join: ch in "characters",
          on: ch.campaign_id == c.id,
          where: ch.id == ^params["character_id"]
      else
        count_query
      end

    count_query =
      if params["vehicle_id"] && params["vehicle_id"] != "" do
        from c in count_query,
          join: v in "vehicles",
          on: v.campaign_id == c.id,
          where: v.id == ^params["vehicle_id"]
      else
        count_query
      end

    count_query = apply_visibility_filter(count_query, params)
    total_count = Repo.aggregate(count_query, :count, :id)

    # Apply pagination
    campaigns =
      query
      |> limit(^per_page)
      |> offset(^offset)
      |> Repo.all()

    # Load image URLs for all campaigns efficiently
    campaigns_with_images = ImageLoader.load_image_urls(campaigns, "Campaign")

    # Return campaigns with pagination metadata
    %{
      campaigns: campaigns_with_images,
      meta: %{
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: div(total_count + per_page - 1, per_page)
      },
      is_autocomplete: params["autocomplete"] == "true" || params["autocomplete"] == true
    }
  end

  defp apply_visibility_filter(query, params) do
    case params["visibility"] do
      "hidden" ->
        from c in query, where: c.active == false

      "all" ->
        query

      _ ->
        # Default to visible (active) only
        from c in query, where: c.active == true
    end
  end

  defp parse_ids(ids_param) when is_binary(ids_param) do
    ids_param
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_ids(ids_param) when is_list(ids_param), do: ids_param
  defp parse_ids(_), do: []

  defp apply_sorting(query, params) do
    sort = params["sort"] || "created_at"
    order = if params["order"] == "ASC", do: :asc, else: :desc

    case sort do
      "name" ->
        order_by(query, [c], [{^order, fragment("LOWER(?)", c.name)}])

      "created_at" ->
        order_by(query, [c], [{^order, c.created_at}])

      "updated_at" ->
        order_by(query, [c], [{^order, c.updated_at}])

      _ ->
        order_by(query, [c], desc: c.created_at)
    end
  end

  def create_campaign(attrs \\ %{}) do
    %Campaign{}
    |> Campaign.changeset(attrs)
    |> Repo.insert()
    |> broadcast_result(:insert)
  end

  def update_campaign(%Campaign{} = campaign, attrs) do
    campaign
    |> Campaign.changeset(attrs)
    |> Repo.update()
    |> broadcast_result(:update)
  end

  def delete_campaign(%Campaign{} = campaign) do
    campaign
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
    |> broadcast_result(:delete)
  end

  def add_member(campaign, user) do
    %CampaignMembership{}
    |> CampaignMembership.changeset(%{campaign_id: campaign.id, user_id: user.id})
    |> Repo.insert()
    |> case do
      {:ok, _membership} = result ->
        broadcast_change(campaign, :update)
        result

      error ->
        error
    end
  end

  def remove_member(campaign, user) do
    query =
      from cm in CampaignMembership,
        where: cm.campaign_id == ^campaign.id and cm.user_id == ^user.id

    case Repo.delete_all(query) do
      {count, _} ->
        if count > 0 do
          broadcast_change(campaign, :update)
        end

        {count, nil}

      other ->
        other
    end
  end

  def is_member?(campaign_id, user_id) do
    query =
      from cm in CampaignMembership,
        where: cm.campaign_id == ^campaign_id and cm.user_id == ^user_id

    Repo.exists?(query)
  end
end
