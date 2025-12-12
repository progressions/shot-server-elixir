defmodule ShotElixir.Workers.BatchImageGenerationWorkerTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Workers.BatchImageGenerationWorker
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Characters.Character
  alias ShotElixir.Sites.Site
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Parties.Party
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.Accounts

  describe "perform/1 entity lookup" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-batch-worker@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Batch Worker Campaign",
          user_id: user.id,
          batch_image_status: "generating",
          batch_images_total: 1,
          batch_images_completed: 0
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "discards job when character not found", %{campaign: campaign} do
      job = %Oban.Job{
        args: %{
          "entity_type" => "Character",
          "entity_id" => Ecto.UUID.generate(),
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:discard, :entity_not_found} = BatchImageGenerationWorker.perform(job)

      # Should still increment counter to prevent blocking
      updated = Repo.get(Campaign, campaign.id)
      assert updated.batch_images_completed == 1
    end

    test "discards job when site not found", %{campaign: campaign} do
      job = %Oban.Job{
        args: %{
          "entity_type" => "Site",
          "entity_id" => Ecto.UUID.generate(),
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:discard, :entity_not_found} = BatchImageGenerationWorker.perform(job)
    end

    test "discards job when faction not found", %{campaign: campaign} do
      job = %Oban.Job{
        args: %{
          "entity_type" => "Faction",
          "entity_id" => Ecto.UUID.generate(),
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:discard, :entity_not_found} = BatchImageGenerationWorker.perform(job)
    end

    test "discards job when party not found", %{campaign: campaign} do
      job = %Oban.Job{
        args: %{
          "entity_type" => "Party",
          "entity_id" => Ecto.UUID.generate(),
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:discard, :entity_not_found} = BatchImageGenerationWorker.perform(job)
    end

    test "discards job when vehicle not found", %{campaign: campaign} do
      job = %Oban.Job{
        args: %{
          "entity_type" => "Vehicle",
          "entity_id" => Ecto.UUID.generate(),
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:discard, :entity_not_found} = BatchImageGenerationWorker.perform(job)
    end

    test "discards job for unsupported entity type", %{campaign: campaign} do
      job = %Oban.Job{
        args: %{
          "entity_type" => "Unknown",
          "entity_id" => Ecto.UUID.generate(),
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      # Should discard job since entity type is not supported
      assert {:discard, :unsupported_type} = BatchImageGenerationWorker.perform(job)

      # Should still increment counter to prevent blocking
      updated = Repo.get(Campaign, campaign.id)
      assert updated.batch_images_completed == 1
    end
  end

  describe "progress tracking integration" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-progress-batch@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Progress Batch Campaign",
          user_id: user.id,
          batch_image_status: "generating",
          batch_images_total: 3,
          batch_images_completed: 0
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "increments counter when entity not found with campaign_id", %{campaign: campaign} do
      job = %Oban.Job{
        args: %{
          "entity_type" => "Character",
          "entity_id" => Ecto.UUID.generate(),
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:discard, :entity_not_found} = BatchImageGenerationWorker.perform(job)

      updated = Repo.get(Campaign, campaign.id)
      assert updated.batch_images_completed == 1
    end

    test "broadcasts progress when job completes with not found", %{campaign: campaign} do
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      job = %Oban.Job{
        args: %{
          "entity_type" => "Character",
          "entity_id" => Ecto.UUID.generate(),
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:discard, :entity_not_found} = BatchImageGenerationWorker.perform(job)

      assert_receive {:campaign_broadcast, payload}
      assert payload.campaign.batch_image_status == "generating"
      assert payload.campaign.batch_images_completed == 1
    end

    test "finalizes batch when last entity completes", %{campaign: campaign} do
      # Set to 2/3 complete
      campaign
      |> Ecto.Changeset.change(batch_images_completed: 2)
      |> Repo.update!()

      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      job = %Oban.Job{
        args: %{
          "entity_type" => "Character",
          "entity_id" => Ecto.UUID.generate(),
          "campaign_id" => campaign.id
        },
        attempt: 1,
        max_attempts: 3
      }

      assert {:discard, :entity_not_found} = BatchImageGenerationWorker.perform(job)

      updated = Repo.get(Campaign, campaign.id)
      assert updated.batch_image_status == "complete"
      assert updated.batch_images_completed == 3
    end
  end

  describe "entity type handling" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-entity-types@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Entity Types Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "can find existing character", %{campaign: campaign, user: user} do
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      # The perform will fail at image generation (external API), but entity lookup should succeed
      # We verify this by checking it doesn't return :entity_not_found
      job = %Oban.Job{
        args: %{
          "entity_type" => "Character",
          "entity_id" => character.id
        },
        attempt: 1,
        max_attempts: 3
      }

      result = BatchImageGenerationWorker.perform(job)
      # Should not be entity_not_found since character exists
      refute match?({:discard, :entity_not_found}, result)
    end

    test "can find existing site", %{campaign: campaign} do
      {:ok, site} =
        %Site{}
        |> Site.changeset(%{
          name: "Test Site",
          campaign_id: campaign.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "entity_type" => "Site",
          "entity_id" => site.id
        },
        attempt: 1,
        max_attempts: 3
      }

      result = BatchImageGenerationWorker.perform(job)
      refute match?({:discard, :entity_not_found}, result)
    end

    test "can find existing faction", %{campaign: campaign} do
      {:ok, faction} =
        %Faction{}
        |> Faction.changeset(%{
          name: "Test Faction",
          campaign_id: campaign.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "entity_type" => "Faction",
          "entity_id" => faction.id
        },
        attempt: 1,
        max_attempts: 3
      }

      result = BatchImageGenerationWorker.perform(job)
      refute match?({:discard, :entity_not_found}, result)
    end

    test "can find existing party", %{campaign: campaign} do
      {:ok, party} =
        %Party{}
        |> Party.changeset(%{
          name: "Test Party",
          campaign_id: campaign.id,
          active: true
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "entity_type" => "Party",
          "entity_id" => party.id
        },
        attempt: 1,
        max_attempts: 3
      }

      result = BatchImageGenerationWorker.perform(job)
      refute match?({:discard, :entity_not_found}, result)
    end

    test "can find existing vehicle", %{campaign: campaign} do
      {:ok, vehicle} =
        %Vehicle{}
        |> Vehicle.changeset(%{
          name: "Test Vehicle",
          campaign_id: campaign.id,
          active: true,
          action_values: %{}
        })
        |> Repo.insert()

      job = %Oban.Job{
        args: %{
          "entity_type" => "Vehicle",
          "entity_id" => vehicle.id
        },
        attempt: 1,
        max_attempts: 3
      }

      result = BatchImageGenerationWorker.perform(job)
      refute match?({:discard, :entity_not_found}, result)
    end
  end

  # Note: Tests for actual image generation would require mocking the GrokService
  # which is an external API. The above tests validate the worker's entity lookup,
  # error handling, and progress tracking integration.
end
