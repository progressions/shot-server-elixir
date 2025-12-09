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
end
