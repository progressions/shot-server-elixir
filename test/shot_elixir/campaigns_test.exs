defmodule ShotElixir.CampaignsTest do
  use ShotElixir.DataCase, async: true
  alias ShotElixir.Campaigns
  alias ShotElixir.Campaigns.{Campaign, CampaignMembership}
  alias ShotElixir.Accounts
  alias ShotElixir.Repo

  describe "campaigns" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, player} =
        Accounts.create_user(%{
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

      {:ok, campaign2} =
        Campaigns.create_campaign(%{
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

      attrs2 =
        Map.merge(@valid_attrs, %{
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
      memberships =
        Repo.all(
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

  describe "list_user_campaigns/3 sorting" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "sorting_gm@example.com",
          password: "password123",
          first_name: "Sort",
          last_name: "Tester",
          gamemaster: true
        })

      # Create campaigns with different names and explicit timestamps
      # Using Repo directly to set specific created_at values for reliable ordering
      now = DateTime.utc_now()

      {:ok, campaign_alpha} =
        Campaigns.create_campaign(%{
          name: "Alpha Campaign",
          description: "First alphabetically",
          user_id: user.id
        })

      # Update created_at to ensure ordering (1 second apart)
      campaign_alpha =
        campaign_alpha
        |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -2, :second)})
        |> Repo.update!()

      {:ok, campaign_beta} =
        Campaigns.create_campaign(%{
          name: "Beta Campaign",
          description: "Second alphabetically",
          user_id: user.id
        })

      campaign_beta =
        campaign_beta
        |> Ecto.Changeset.change(%{created_at: DateTime.add(now, -1, :second)})
        |> Repo.update!()

      {:ok, campaign_gamma} =
        Campaigns.create_campaign(%{
          name: "Gamma Campaign",
          description: "Third alphabetically",
          user_id: user.id
        })

      campaign_gamma =
        campaign_gamma
        |> Ecto.Changeset.change(%{created_at: now})
        |> Repo.update!()

      {:ok,
       user: user,
       campaign_alpha: campaign_alpha,
       campaign_beta: campaign_beta,
       campaign_gamma: campaign_gamma}
    end

    test "sorts by created_at ascending with lowercase 'asc'", %{
      user: user,
      campaign_alpha: campaign_alpha,
      campaign_gamma: campaign_gamma
    } do
      result = Campaigns.list_user_campaigns(user.id, %{"sort" => "created_at", "order" => "asc"})
      campaign_ids = Enum.map(result.campaigns, & &1.id)

      alpha_idx = Enum.find_index(campaign_ids, &(&1 == campaign_alpha.id))
      gamma_idx = Enum.find_index(campaign_ids, &(&1 == campaign_gamma.id))

      assert alpha_idx < gamma_idx,
             "Alpha should come before Gamma when sorting by created_at asc"
    end

    test "sorts by created_at descending with lowercase 'desc'", %{
      user: user,
      campaign_alpha: campaign_alpha,
      campaign_gamma: campaign_gamma
    } do
      result =
        Campaigns.list_user_campaigns(user.id, %{"sort" => "created_at", "order" => "desc"})

      campaign_ids = Enum.map(result.campaigns, & &1.id)

      alpha_idx = Enum.find_index(campaign_ids, &(&1 == campaign_alpha.id))
      gamma_idx = Enum.find_index(campaign_ids, &(&1 == campaign_gamma.id))

      assert gamma_idx < alpha_idx,
             "Gamma should come before Alpha when sorting by created_at desc"
    end

    test "sorts by name ascending with lowercase 'asc'", %{
      user: user,
      campaign_alpha: campaign_alpha,
      campaign_gamma: campaign_gamma
    } do
      result = Campaigns.list_user_campaigns(user.id, %{"sort" => "name", "order" => "asc"})
      campaign_ids = Enum.map(result.campaigns, & &1.id)

      alpha_idx = Enum.find_index(campaign_ids, &(&1 == campaign_alpha.id))
      gamma_idx = Enum.find_index(campaign_ids, &(&1 == campaign_gamma.id))

      assert alpha_idx < gamma_idx, "Alpha should come before Gamma when sorting by name asc"
    end

    test "sorts by name descending with lowercase 'desc'", %{
      user: user,
      campaign_alpha: campaign_alpha,
      campaign_gamma: campaign_gamma
    } do
      result = Campaigns.list_user_campaigns(user.id, %{"sort" => "name", "order" => "desc"})
      campaign_ids = Enum.map(result.campaigns, & &1.id)

      alpha_idx = Enum.find_index(campaign_ids, &(&1 == campaign_alpha.id))
      gamma_idx = Enum.find_index(campaign_ids, &(&1 == campaign_gamma.id))

      assert gamma_idx < alpha_idx, "Gamma should come before Alpha when sorting by name desc"
    end

    test "handles uppercase 'ASC' for backwards compatibility", %{
      user: user,
      campaign_alpha: campaign_alpha,
      campaign_gamma: campaign_gamma
    } do
      result = Campaigns.list_user_campaigns(user.id, %{"sort" => "created_at", "order" => "ASC"})
      campaign_ids = Enum.map(result.campaigns, & &1.id)

      alpha_idx = Enum.find_index(campaign_ids, &(&1 == campaign_alpha.id))
      gamma_idx = Enum.find_index(campaign_ids, &(&1 == campaign_gamma.id))

      assert alpha_idx < gamma_idx, "Should handle uppercase ASC"
    end

    test "defaults to descending when order is not specified", %{
      user: user,
      campaign_alpha: campaign_alpha,
      campaign_gamma: campaign_gamma
    } do
      result = Campaigns.list_user_campaigns(user.id, %{"sort" => "created_at"})
      campaign_ids = Enum.map(result.campaigns, & &1.id)

      alpha_idx = Enum.find_index(campaign_ids, &(&1 == campaign_alpha.id))
      gamma_idx = Enum.find_index(campaign_ids, &(&1 == campaign_gamma.id))

      assert gamma_idx < alpha_idx, "Should default to descending order"
    end
  end
end
