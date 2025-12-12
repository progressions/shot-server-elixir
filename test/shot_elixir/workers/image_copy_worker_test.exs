defmodule ShotElixir.Workers.ImageCopyWorkerTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Workers.ImageCopyWorker
  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Characters.Character
  alias ShotElixir.Schticks
  alias ShotElixir.Weapons

  describe "perform/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-image-worker@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Image Worker Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "returns :ok when source has no image", %{campaign: campaign, user: user} do
      # Create two characters with no images
      {:ok, source} =
        %Character{}
        |> Character.changeset(%{
          name: "Source Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, target} =
        %Character{}
        |> Character.changeset(%{
          name: "Target Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Character",
          "source_id" => source.id,
          "target_type" => "Character",
          "target_id" => target.id
        }
      }

      # Should complete successfully even when no image exists
      assert :ok = ImageCopyWorker.perform(job)
    end

    test "discards job when source entity not found", %{campaign: campaign, user: user} do
      {:ok, target} =
        %Character{}
        |> Character.changeset(%{
          name: "Target Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Character",
          "source_id" => Ecto.UUID.generate(),
          "target_type" => "Character",
          "target_id" => target.id
        }
      }

      assert {:discard, :entity_not_found} = ImageCopyWorker.perform(job)
    end

    test "discards job when target entity not found", %{campaign: campaign, user: user} do
      {:ok, source} =
        %Character{}
        |> Character.changeset(%{
          name: "Source Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Character",
          "source_id" => source.id,
          "target_type" => "Character",
          "target_id" => Ecto.UUID.generate()
        }
      }

      assert {:discard, :entity_not_found} = ImageCopyWorker.perform(job)
    end

    test "handles schtick entities", %{campaign: campaign} do
      {:ok, source} =
        Schticks.create_schtick(%{
          name: "Source Schtick",
          category: "Guns",
          campaign_id: campaign.id
        })

      {:ok, target} =
        Schticks.create_schtick(%{
          name: "Target Schtick",
          category: "Guns",
          campaign_id: campaign.id
        })

      job = %Oban.Job{
        args: %{
          "source_type" => "Schtick",
          "source_id" => source.id,
          "target_type" => "Schtick",
          "target_id" => target.id
        }
      }

      assert :ok = ImageCopyWorker.perform(job)
    end

    test "handles weapon entities", %{campaign: campaign} do
      {:ok, source} =
        Weapons.create_weapon(%{
          name: "Source Weapon",
          damage: 10,
          campaign_id: campaign.id
        })

      {:ok, target} =
        Weapons.create_weapon(%{
          name: "Target Weapon",
          damage: 10,
          campaign_id: campaign.id
        })

      job = %Oban.Job{
        args: %{
          "source_type" => "Weapon",
          "source_id" => source.id,
          "target_type" => "Weapon",
          "target_id" => target.id
        }
      }

      assert :ok = ImageCopyWorker.perform(job)
    end

    test "handles campaign entities", %{user: user} do
      {:ok, source} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Source Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, target} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Target Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Campaign",
          "source_id" => source.id,
          "target_type" => "Campaign",
          "target_id" => target.id
        }
      }

      assert :ok = ImageCopyWorker.perform(job)
    end
  end

  describe "campaign_id progress tracking" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-progress-tracking@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Progress Tracking Campaign",
          user_id: user.id,
          seeding_status: "images",
          seeding_images_total: 3,
          seeding_images_completed: 0
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "increments seeding_images_completed when campaign_id provided", %{
      campaign: campaign,
      user: user
    } do
      # Create source and target characters
      {:ok, source} =
        %Character{}
        |> Character.changeset(%{
          name: "Source Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, target} =
        %Character{}
        |> Character.changeset(%{
          name: "Target Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Character",
          "source_id" => source.id,
          "target_type" => "Character",
          "target_id" => target.id,
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert :ok = ImageCopyWorker.perform(job)

      # Verify counter was incremented
      updated_campaign = Repo.get(Campaign, campaign.id)
      assert updated_campaign.seeding_images_completed == 1
    end

    test "finalizes seeding when all images complete", %{campaign: campaign, user: user} do
      # Set campaign to be 2/3 complete
      campaign
      |> Ecto.Changeset.change(seeding_images_completed: 2)
      |> Repo.update!()

      # Create characters for the final image job
      {:ok, source} =
        %Character{}
        |> Character.changeset(%{
          name: "Source Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, target} =
        %Character{}
        |> Character.changeset(%{
          name: "Target Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Character",
          "source_id" => source.id,
          "target_type" => "Character",
          "target_id" => target.id,
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert :ok = ImageCopyWorker.perform(job)

      # Verify seeding is complete
      updated_campaign = Repo.get(Campaign, campaign.id)
      assert updated_campaign.seeding_images_completed == 3
      assert updated_campaign.seeding_status == "complete"
      assert updated_campaign.seeded_at != nil
    end

    test "increments counter when entity not found with campaign_id", %{
      campaign: campaign,
      user: user
    } do
      {:ok, target} =
        %Character{}
        |> Character.changeset(%{
          name: "Target Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Character",
          "source_id" => Ecto.UUID.generate(),
          "target_type" => "Character",
          "target_id" => target.id,
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:discard, :entity_not_found} = ImageCopyWorker.perform(job)

      # Counter should still be incremented even for not found entities
      updated_campaign = Repo.get(Campaign, campaign.id)
      assert updated_campaign.seeding_images_completed == 1
    end

    test "broadcasts progress updates to campaign channel", %{user: user} do
      # Create a unique campaign for this test to avoid async test interference
      {:ok, test_campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Broadcast Test Campaign",
          user_id: user.id,
          seeding_status: "images",
          seeding_images_total: 3,
          seeding_images_completed: 0
        })
        |> Repo.insert()

      # Verify starting state
      assert test_campaign.seeding_images_completed == 0

      # Subscribe to the campaign channel
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{test_campaign.id}")

      {:ok, source} =
        %Character{}
        |> Character.changeset(%{
          name: "Source Character",
          campaign_id: test_campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, target} =
        %Character{}
        |> Character.changeset(%{
          name: "Target Character",
          campaign_id: test_campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Character",
          "source_id" => source.id,
          "target_type" => "Character",
          "target_id" => target.id,
          "campaign_id" => test_campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert :ok = ImageCopyWorker.perform(job)

      # Verify database was updated
      updated = Repo.get(Campaign, test_campaign.id)
      assert updated.seeding_images_completed == 1

      # Verify broadcast was sent with correct structure
      assert_receive {:campaign_broadcast, payload}
      assert payload.seeding_status == "images"
      assert payload.campaign_id == test_campaign.id
      # The broadcast should reflect the new count
      assert payload.images_completed == 1
      assert payload.images_total == 3
    end

    test "broadcasts to user channel for newly created campaigns", %{
      campaign: campaign,
      user: user
    } do
      # Subscribe to the user channel
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "user:#{user.id}")

      {:ok, source} =
        %Character{}
        |> Character.changeset(%{
          name: "Source Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, target} =
        %Character{}
        |> Character.changeset(%{
          name: "Target Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Character",
          "source_id" => source.id,
          "target_type" => "Character",
          "target_id" => target.id,
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert :ok = ImageCopyWorker.perform(job)

      # Verify broadcast was sent to user channel
      assert_receive {:user_broadcast, payload}
      assert payload.seeding_status == "images"
      assert payload.campaign_id == campaign.id
    end

    test "broadcasts completion when seeding finishes", %{campaign: campaign, user: user} do
      # Set campaign to be 2/3 complete
      campaign
      |> Ecto.Changeset.change(seeding_images_completed: 2)
      |> Repo.update!()

      # Subscribe to the campaign channel
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      {:ok, source} =
        %Character{}
        |> Character.changeset(%{
          name: "Source Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, target} =
        %Character{}
        |> Character.changeset(%{
          name: "Target Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "source_type" => "Character",
          "source_id" => source.id,
          "target_type" => "Character",
          "target_id" => target.id,
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert :ok = ImageCopyWorker.perform(job)

      # Verify progress broadcast
      assert_receive {:campaign_broadcast, progress_payload}
      assert progress_payload.seeding_status == "images"

      # Verify completion broadcast
      assert_receive {:campaign_broadcast, completion_payload}
      assert completion_payload.seeding_status == "complete"

      # Verify legacy campaign_seeded event
      assert_receive {:campaign_seeded, seeded_payload}
      assert seeded_payload.campaign_id == campaign.id
    end
  end

  describe "finalize_seeding race condition handling" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-race-condition@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Race Condition Campaign",
          user_id: user.id,
          seeding_status: "images",
          seeding_images_total: 1,
          seeding_images_completed: 0
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "only one worker finalizes seeding when multiple complete simultaneously", %{
      campaign: campaign
    } do
      # First finalization should succeed
      assert :ok = ImageCopyWorker.finalize_seeding(campaign)

      updated_campaign = Repo.get(Campaign, campaign.id)
      assert updated_campaign.seeding_status == "complete"

      # Second finalization should be a no-op (already complete)
      assert :ok = ImageCopyWorker.finalize_seeding(campaign)

      # Status should still be complete
      still_complete = Repo.get(Campaign, campaign.id)
      assert still_complete.seeding_status == "complete"
    end

    test "finalize_seeding skips if status already complete", %{campaign: campaign} do
      # Mark as already complete
      campaign
      |> Ecto.Changeset.change(seeding_status: "complete")
      |> Repo.update!()

      # Subscribe to check for broadcasts
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      # Should skip finalization since already complete
      assert :ok = ImageCopyWorker.finalize_seeding(campaign)

      # Should not receive any completion broadcasts (since it was already complete)
      refute_receive {:campaign_broadcast, _}, 100
    end
  end
end
