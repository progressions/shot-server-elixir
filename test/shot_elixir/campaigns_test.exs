defmodule ShotElixir.CampaignsTest do
  use ShotElixir.DataCase
  alias ShotElixir.Campaigns
  alias ShotElixir.Campaigns.{Campaign, CampaignMembership}
  alias ShotElixir.Accounts

  describe "campaigns" do
    setup do
      {:ok, user} = Accounts.create_user(%{
        email: "gm@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

      {:ok, player} = Accounts.create_user(%{
        email: "player@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "One"
      })

      {:ok, user: user, player: player}
    end

    @valid_attrs %{
      name: "Test Campaign",
      description: "A test campaign",
      active: true
    }

    @update_attrs %{
      name: "Updated Campaign",
      description: "Updated description",
      active: false
    }

    @invalid_attrs %{name: nil, user_id: nil}

    test "list_campaigns/0 returns all campaigns", %{user: user} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      campaigns = Campaigns.list_campaigns()
      assert Enum.any?(campaigns, fn c -> c.id == campaign.id end)
    end

    test "get_campaign!/1 returns the campaign with given id", %{user: user} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      fetched = Campaigns.get_campaign!(campaign.id)
      assert fetched.id == campaign.id
    end

    test "get_campaign/1 returns the campaign with given id", %{user: user} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      fetched = Campaigns.get_campaign(campaign.id)
      assert fetched.id == campaign.id
    end

    test "get_campaign/1 returns nil for invalid id" do
      assert Campaigns.get_campaign(Ecto.UUID.generate()) == nil
    end

    test "get_user_campaigns/1 returns campaigns owned by user", %{user: user} do
      {:ok, campaign1} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      {:ok, campaign2} = Campaigns.create_campaign(%{
        name: "Another Campaign",
        description: "Another test",
        user_id: user.id
      })

      campaigns = Campaigns.get_user_campaigns(user.id)
      campaign_ids = Enum.map(campaigns, & &1.id)

      assert campaign1.id in campaign_ids
      assert campaign2.id in campaign_ids
    end

    test "get_user_campaigns/1 returns campaigns user is member of", %{user: user, player: player} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      {:ok, _} = Campaigns.add_member(campaign, player)

      campaigns = Campaigns.get_user_campaigns(player.id)
      assert Enum.any?(campaigns, fn c -> c.id == campaign.id end)
    end

    test "create_campaign/1 with valid data creates a campaign", %{user: user} do
      attrs = Map.put(@valid_attrs, :user_id, user.id)
      assert {:ok, %Campaign{} = campaign} = Campaigns.create_campaign(attrs)
      assert campaign.name == "Test Campaign"
      assert campaign.description == "A test campaign"
      assert campaign.active == true
      assert campaign.user_id == user.id
    end

    test "create_campaign/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Campaigns.create_campaign(@invalid_attrs)
    end

    test "create_campaign/1 enforces unique name per user", %{user: user} do
      attrs = Map.put(@valid_attrs, :user_id, user.id)
      {:ok, _} = Campaigns.create_campaign(attrs)
      assert {:error, %Ecto.Changeset{}} = Campaigns.create_campaign(attrs)
    end

    test "create_campaign/1 allows only one master template", %{user: user} do
      attrs1 = Map.merge(@valid_attrs, %{user_id: user.id, is_master_template: true})
      {:ok, _} = Campaigns.create_campaign(attrs1)

      attrs2 = Map.merge(@valid_attrs, %{
        name: "Second Campaign",
        user_id: user.id,
        is_master_template: true
      })
      assert {:error, %Ecto.Changeset{} = changeset} = Campaigns.create_campaign(attrs2)
      errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
      assert errors[:is_master_template]
    end

    test "update_campaign/2 with valid data updates the campaign", %{user: user} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      assert {:ok, updated} = Campaigns.update_campaign(campaign, @update_attrs)
      assert updated.name == "Updated Campaign"
      assert updated.description == "Updated description"
      assert updated.active == false
    end

    test "update_campaign/2 with invalid data returns error changeset", %{user: user} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      assert {:error, %Ecto.Changeset{}} = Campaigns.update_campaign(campaign, @invalid_attrs)
      fetched = Campaigns.get_campaign!(campaign.id)
      assert fetched.name == campaign.name
    end

    test "delete_campaign/1 soft deletes the campaign", %{user: user} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      assert {:ok, deleted} = Campaigns.delete_campaign(campaign)
      assert deleted.active == false
    end

    test "add_member/2 adds user as campaign member", %{user: user, player: player} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      assert {:ok, %CampaignMembership{} = membership} = Campaigns.add_member(campaign, player)
      assert membership.campaign_id == campaign.id
      assert membership.user_id == player.id
    end

    test "add_member/2 prevents duplicate memberships", %{user: user, player: player} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      {:ok, _} = Campaigns.add_member(campaign, player)
      assert {:error, %Ecto.Changeset{}} = Campaigns.add_member(campaign, player)
    end

    test "remove_member/2 removes user from campaign", %{user: user, player: player} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      {:ok, _} = Campaigns.add_member(campaign, player)

      assert {1, nil} = Campaigns.remove_member(campaign, player)

      # Verify member was removed
      memberships = Repo.all(
        from cm in CampaignMembership,
        where: cm.campaign_id == ^campaign.id and cm.user_id == ^player.id
      )
      assert memberships == []
    end

    test "remove_member/2 returns 0 if member doesn't exist", %{user: user, player: player} do
      {:ok, campaign} = Campaigns.create_campaign(Map.put(@valid_attrs, :user_id, user.id))
      assert {0, nil} = Campaigns.remove_member(campaign, player)
    end
  end
end