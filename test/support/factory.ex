defmodule ShotElixir.Factory do
  @moduledoc """
  Factory functions for creating test data.
  """

  alias ShotElixir.{Repo, Accounts, Campaigns, Characters, Fights}

  def insert(type, attrs \\ %{})

  def insert(:user, attrs) do
    defaults = %{
      email: "user#{System.unique_integer([:positive])}@example.com",
      password: "password123",
      first_name: "Test",
      last_name: "User",
      gamemaster: false,
      admin: false
    }

    {:ok, user} = Accounts.create_user(Map.merge(defaults, attrs))
    user
  end

  def insert(:campaign, attrs) do
    user = attrs[:user] || insert(:user, %{gamemaster: true})

    defaults = %{
      name: "Test Campaign #{System.unique_integer([:positive])}",
      description: "A test campaign",
      user_id: user.id
    }

    {:ok, campaign} = Campaigns.create_campaign(Map.merge(defaults, attrs))
    campaign
  end

  def insert(:campaign_user, attrs) do
    user = attrs[:user] || insert(:user)
    campaign = attrs[:campaign] || insert(:campaign)

    {:ok, _} = Campaigns.add_member(campaign, user)
    %{user: user, campaign: campaign}
  end

  def insert(:character, attrs) do
    user = attrs[:user] || insert(:user)
    campaign = attrs[:campaign] || insert(:campaign)

    defaults = %{
      name: "Test Character #{System.unique_integer([:positive])}",
      campaign_id: campaign.id,
      user_id: user.id,
      action_values: %{"Type" => "PC"}
    }

    {:ok, character} = Characters.create_character(Map.merge(defaults, attrs))
    character
  end

  def insert(:fight, attrs) do
    campaign = attrs[:campaign] || insert(:campaign)

    defaults = %{
      name: "Test Fight #{System.unique_integer([:positive])}",
      campaign_id: campaign.id,
      shot_counter: 18,
      sequence: 1
    }

    {:ok, fight} = Fights.create_fight(Map.merge(defaults, attrs))
    fight
  end

  def insert(:shot, attrs) do
    fight = attrs[:fight] || insert(:fight)
    character = attrs[:character] || insert(:character)

    defaults = %{
      fight_id: fight.id,
      character_id: character.id,
      shot: 10,
      acted: false
    }

    {:ok, shot} = Fights.create_shot(Map.merge(defaults, attrs))
    shot
  end
end