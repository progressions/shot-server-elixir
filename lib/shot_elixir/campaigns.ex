defmodule ShotElixir.Campaigns do
  @moduledoc """
  The Campaigns context.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Campaigns.CampaignMembership

  def list_campaigns do
    Repo.all(Campaign)
  end

  def get_campaign!(id), do: Repo.get!(Campaign, id)
  def get_campaign(id), do: Repo.get(Campaign, id)

  def get_user_campaigns(user_id) do
    query = from c in Campaign,
      left_join: cm in CampaignMembership, on: cm.campaign_id == c.id,
      where: c.user_id == ^user_id or cm.user_id == ^user_id,
      distinct: true

    Repo.all(query)
  end

  def create_campaign(attrs \\ %{}) do
    %Campaign{}
    |> Campaign.changeset(attrs)
    |> Repo.insert()
  end

  def update_campaign(%Campaign{} = campaign, attrs) do
    campaign
    |> Campaign.changeset(attrs)
    |> Repo.update()
  end

  def delete_campaign(%Campaign{} = campaign) do
    campaign
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def add_member(campaign, user) do
    %CampaignMembership{}
    |> CampaignMembership.changeset(%{campaign_id: campaign.id, user_id: user.id})
    |> Repo.insert()
  end

  def remove_member(campaign, user) do
    query = from cm in CampaignMembership,
      where: cm.campaign_id == ^campaign.id and cm.user_id == ^user.id

    Repo.delete_all(query)
  end
end