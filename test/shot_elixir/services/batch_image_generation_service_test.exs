defmodule ShotElixir.Services.BatchImageGenerationServiceTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Services.BatchImageGenerationService
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Characters.Character
  alias ShotElixir.Sites.Site
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Accounts

  describe "find_entities_without_images/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-batch-test@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Batch Test Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "returns empty list when all entities have images", %{campaign: campaign} do
      entities = BatchImageGenerationService.find_entities_without_images(campaign.id)
      assert entities == []
    end

    test "finds characters without images", %{campaign: campaign, user: user} do
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      entities = BatchImageGenerationService.find_entities_without_images(campaign.id)
      assert {character.id, "Character"} in entities
    end

    test "finds sites without images", %{campaign: campaign} do
      {:ok, site} =
        %Site{}
        |> Site.changeset(%{
          name: "Test Site",
          campaign_id: campaign.id,
          active: true
        })
        |> Repo.insert()

      entities = BatchImageGenerationService.find_entities_without_images(campaign.id)
      assert {site.id, "Site"} in entities
    end

    test "finds factions without images", %{campaign: campaign} do
      {:ok, faction} =
        %Faction{}
        |> Faction.changeset(%{
          name: "Test Faction",
          campaign_id: campaign.id,
          active: true
        })
        |> Repo.insert()

      entities = BatchImageGenerationService.find_entities_without_images(campaign.id)
      assert {faction.id, "Faction"} in entities
    end

    test "does not include inactive entities", %{campaign: campaign, user: user} do
      {:ok, _inactive} =
        %Character{}
        |> Character.changeset(%{
          name: "Inactive Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: false
        })
        |> Repo.insert()

      entities = BatchImageGenerationService.find_entities_without_images(campaign.id)
      assert entities == []
    end
  end

  describe "start_batch_generation/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-batch-start@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Batch Start Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "returns error when campaign not found" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :campaign_not_found} =
               BatchImageGenerationService.start_batch_generation(fake_id)
    end

    test "returns error when no entities without images", %{campaign: campaign} do
      assert {:error, :no_entities_without_images} =
               BatchImageGenerationService.start_batch_generation(campaign.id)
    end

    test "returns error when batch already in progress", %{campaign: campaign, user: user} do
      # Create an entity without an image
      {:ok, _character} =
        %Character{}
        |> Character.changeset(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      # Set campaign to already generating
      campaign
      |> Ecto.Changeset.change(batch_image_status: "generating")
      |> Repo.update!()

      assert {:error, {:already_in_progress, "generating"}} =
               BatchImageGenerationService.start_batch_generation(campaign.id)
    end

    test "starts batch generation and updates campaign status", %{campaign: campaign, user: user} do
      {:ok, _char1} =
        %Character{}
        |> Character.changeset(%{
          name: "Character 1",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, _char2} =
        %Character{}
        |> Character.changeset(%{
          name: "Character 2",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      # Use manual mode to prevent jobs from executing immediately
      # This allows us to test the start_batch_generation function's behavior
      # without the worker jobs interfering
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, 2} = BatchImageGenerationService.start_batch_generation(campaign.id)

        updated = Repo.get(Campaign, campaign.id)
        assert updated.batch_image_status == "generating"
        assert updated.batch_images_total == 2
        assert updated.batch_images_completed == 0
      end)
    end

    test "broadcasts initial status to campaign channel", %{campaign: campaign, user: user} do
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      {:ok, _character} =
        %Character{}
        |> Character.changeset(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      # Use manual mode to prevent jobs from executing immediately
      # This ensures we only receive the initial broadcast, not job-related broadcasts
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, 1} = BatchImageGenerationService.start_batch_generation(campaign.id)

        assert_receive {:campaign_broadcast, payload}
        assert payload.campaign.batch_image_status == "generating"
        assert payload.campaign.batch_images_completed == 0
        assert payload.campaign.batch_images_total == 1
      end)
    end
  end

  describe "increment_completion/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-increment@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Increment Campaign",
          user_id: user.id,
          batch_image_status: "generating",
          batch_images_total: 3,
          batch_images_completed: 0
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "increments completion counter atomically", %{campaign: campaign} do
      assert {:ok, 1} = BatchImageGenerationService.increment_completion(campaign.id)

      updated = Repo.get(Campaign, campaign.id)
      assert updated.batch_images_completed == 1
    end

    test "returns error when campaign not found" do
      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = BatchImageGenerationService.increment_completion(fake_id)
    end

    test "broadcasts progress to campaign channel", %{campaign: campaign} do
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      assert {:ok, 1} = BatchImageGenerationService.increment_completion(campaign.id)

      assert_receive {:campaign_broadcast, payload}
      assert payload.campaign.batch_image_status == "generating"
      assert payload.campaign.batch_images_completed == 1
    end

    test "finalizes when all images complete", %{campaign: campaign} do
      # Set to 2/3 complete
      campaign
      |> Ecto.Changeset.change(batch_images_completed: 2)
      |> Repo.update!()

      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      assert {:ok, 3} = BatchImageGenerationService.increment_completion(campaign.id)

      updated = Repo.get(Campaign, campaign.id)
      assert updated.batch_image_status == "complete"

      # Should receive completion broadcast
      assert_receive {:campaign_broadcast, _progress_payload}
      assert_receive {:campaign_broadcast, completion_payload}
      assert completion_payload.campaign.batch_image_status == "complete"
    end
  end

  describe "finalize_batch_generation/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-finalize@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Finalize Campaign",
          user_id: user.id,
          batch_image_status: "generating",
          batch_images_total: 3,
          batch_images_completed: 3
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "marks batch as complete", %{campaign: campaign} do
      assert :ok = BatchImageGenerationService.finalize_batch_generation(campaign)

      updated = Repo.get(Campaign, campaign.id)
      assert updated.batch_image_status == "complete"
    end

    test "broadcasts completion status", %{campaign: campaign} do
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      assert :ok = BatchImageGenerationService.finalize_batch_generation(campaign)

      assert_receive {:campaign_broadcast, payload}
      assert payload.campaign.batch_image_status == "complete"
    end

    test "returns :already_complete if already finalized", %{campaign: campaign} do
      # First finalization
      assert :ok = BatchImageGenerationService.finalize_batch_generation(campaign)

      # Second finalization should return :already_complete
      assert :already_complete = BatchImageGenerationService.finalize_batch_generation(campaign)
    end

    test "handles race condition - only one worker finalizes", %{campaign: campaign} do
      # Simulate two workers trying to finalize simultaneously
      result1 = BatchImageGenerationService.finalize_batch_generation(campaign)
      result2 = BatchImageGenerationService.finalize_batch_generation(campaign)

      # One should succeed, one should return already_complete
      assert :ok in [result1, result2]
      assert :already_complete in [result1, result2]

      # Status should be complete
      updated = Repo.get(Campaign, campaign.id)
      assert updated.batch_image_status == "complete"
    end
  end
end
