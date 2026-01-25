defmodule ShotElixir.Factory do
  @moduledoc """
  Factory functions for creating test data.
  """

  alias ShotElixir.{Accounts, Campaigns, Characters, Fights}
  alias ShotElixir.{Sites, Parties}

  def insert(type, attrs \\ %{})

  def insert(:user, attrs) do
    # Convert keyword list to map if necessary
    attrs = Enum.into(attrs, %{})

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
    # Convert keyword list to map if necessary
    attrs = Enum.into(attrs, %{})

    user = attrs[:user] || insert(:user, %{gamemaster: true})

    # Remove :user from attrs to avoid conflict with user_id
    attrs_without_user = Map.delete(attrs, :user)

    defaults = %{
      name: "Test Campaign #{System.unique_integer([:positive])}",
      description: "A test campaign",
      user_id: user.id
    }

    {:ok, campaign} = Campaigns.create_campaign(Map.merge(defaults, attrs_without_user))
    campaign
  end

  def insert(:campaign_user, attrs) do
    # Convert keyword list to map if necessary
    attrs = Enum.into(attrs, %{})

    user = attrs[:user] || insert(:user)
    campaign = attrs[:campaign] || insert(:campaign)

    {:ok, _} = Campaigns.add_member(campaign, user)
    %{user: user, campaign: campaign}
  end

  def insert(:character, attrs) do
    # Convert keyword list to map if necessary
    attrs = Enum.into(attrs, %{})

    user = attrs[:user] || insert(:user)
    campaign = attrs[:campaign] || insert(:campaign)

    # Remove :user and :campaign from attrs to avoid conflicts
    attrs_cleaned = attrs |> Map.delete(:user) |> Map.delete(:campaign)

    defaults = %{
      name: "Test Character #{System.unique_integer([:positive])}",
      campaign_id: campaign.id,
      user_id: user.id,
      action_values: %{"Type" => "PC"}
    }

    {:ok, character} = Characters.create_character(Map.merge(defaults, attrs_cleaned))
    character
  end

  def insert(:site, attrs) do
    attrs = Enum.into(attrs, %{})

    user = attrs[:user] || insert(:user)
    campaign = attrs[:campaign] || insert(:campaign)

    attrs_cleaned = attrs |> Map.delete(:user) |> Map.delete(:campaign)

    defaults = %{
      name: "Test Site #{System.unique_integer([:positive])}",
      campaign_id: campaign.id,
      user_id: user.id
    }

    {:ok, site} = Sites.create_site(Map.merge(defaults, attrs_cleaned))
    site
  end

  def insert(:party, attrs) do
    attrs = Enum.into(attrs, %{})

    user = attrs[:user] || insert(:user)
    campaign = attrs[:campaign] || insert(:campaign)

    attrs_cleaned = attrs |> Map.delete(:user) |> Map.delete(:campaign)

    defaults = %{
      name: "Test Party #{System.unique_integer([:positive])}",
      campaign_id: campaign.id,
      user_id: user.id
    }

    {:ok, party} = Parties.create_party(Map.merge(defaults, attrs_cleaned))
    party
  end

  def insert(:fight, attrs) do
    # Convert keyword list to map if necessary
    attrs = Enum.into(attrs, %{})

    campaign = attrs[:campaign] || insert(:campaign)

    # Remove :campaign from attrs if present to avoid conflict with campaign_id
    attrs_without_campaign = Map.delete(attrs, :campaign)

    defaults = %{
      name: "Test Fight #{System.unique_integer([:positive])}",
      campaign_id: campaign.id,
      shot_counter: 18,
      sequence: 1
    }

    {:ok, fight} = Fights.create_fight(Map.merge(defaults, attrs_without_campaign))
    fight
  end

  def insert(:shot, attrs) do
    # Convert keyword list to map if necessary
    attrs = Enum.into(attrs, %{})

    fight = attrs[:fight] || insert(:fight)
    character = attrs[:character] || insert(:character)

    # Remove :fight and :character from attrs to avoid conflicts
    attrs_cleaned = attrs |> Map.delete(:fight) |> Map.delete(:character)

    defaults = %{
      fight_id: fight.id,
      character_id: character.id,
      shot: 10,
      acted: false
    }

    {:ok, shot} = Fights.create_shot(Map.merge(defaults, attrs_cleaned))
    shot
  end

  def insert(:location, attrs) do
    # Convert keyword list to map if necessary
    attrs = Enum.into(attrs, %{})

    # Location must belong to either a fight or a site
    fight = attrs[:fight]
    site = attrs[:site]

    # Remove :fight and :site from attrs to avoid conflicts
    attrs_cleaned = attrs |> Map.delete(:fight) |> Map.delete(:site)

    defaults = %{
      "name" => "Test Location #{System.unique_integer([:positive])}"
    }

    # Convert atom keys to strings for Ecto
    string_attrs =
      Enum.into(attrs_cleaned, %{}, fn
        {k, v} when is_atom(k) -> {Atom.to_string(k), v}
        {k, v} -> {k, v}
      end)

    attrs_with_defaults = Map.merge(defaults, string_attrs)

    # Create via the appropriate context function
    {:ok, location} =
      cond do
        fight -> Fights.create_fight_location(fight.id, attrs_with_defaults)
        site -> Fights.create_site_location(site.id, attrs_with_defaults)
        true -> raise "Location must belong to a fight or site"
      end

    location
  end
end
