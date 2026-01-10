defmodule ShotElixir.Services.NotionServiceTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Services.NotionService
  alias ShotElixir.Characters
  alias ShotElixir.Characters.Character
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Accounts

  describe "handle_archived_page/4" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-notion-test@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Notion Test Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      {:ok, user: user, campaign: campaign, character: character}
    end

    test "clears notion_page_id from character when page is archived", %{character: character} do
      # Character starts with a notion_page_id
      assert character.notion_page_id != nil

      payload = %{"page_id" => character.notion_page_id, "properties" => %{}}

      response = %{
        "code" => "validation_error",
        "message" =>
          "Can't edit block that is archived. You must unarchive the block before editing.",
        "object" => "error",
        "status" => 400
      }

      assert {:ok, :unlinked} =
               NotionService.handle_archived_page(
                 character,
                 payload,
                 response,
                 response["message"]
               )

      # Verify the notion_page_id was cleared
      updated_character = Repo.get(Character, character.id)
      assert updated_character.notion_page_id == nil
    end

    test "creates a notion sync log entry when unlinking", %{character: character} do
      payload = %{"page_id" => character.notion_page_id, "properties" => %{}}

      response = %{
        "code" => "validation_error",
        "message" => "Can't edit block that is archived.",
        "object" => "error",
        "status" => 400
      }

      assert {:ok, :unlinked} =
               NotionService.handle_archived_page(
                 character,
                 payload,
                 response,
                 response["message"]
               )

      # Verify a sync log was created
      logs =
        ShotElixir.Notion.NotionSyncLog
        |> Ecto.Query.where(character_id: ^character.id)
        |> Repo.all()

      assert length(logs) == 1
      log = hd(logs)
      assert log.status == "error"
      assert String.contains?(log.error_message, "unlinking from character")
    end

    test "returns success so Oban worker doesn't retry", %{character: character} do
      payload = %{"page_id" => character.notion_page_id}
      response = %{"code" => "object_not_found", "message" => "Page not found"}

      result =
        NotionService.handle_archived_page(
          character,
          payload,
          response,
          response["message"]
        )

      # Should return {:ok, :unlinked} not {:error, ...}
      assert {:ok, :unlinked} = result
    end
  end

  describe "update_notion_from_character/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-notion-update-test@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Notion Update Test Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "returns error when character has no notion_page_id", %{campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "No Notion Character",
          campaign_id: campaign.id
        })

      assert {:error, :no_page_id} = NotionService.update_notion_from_character(character)
    end
  end

  describe "smart merge logic - character value preservation" do
    # These tests verify that characters preserve their values correctly
    # The actual merge_with_notion function requires mocking NotionClient
    # which is tested via integration tests in the test environment

    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-merge-test@example.com",
          password: "password123",
          first_name: "Merge",
          last_name: "Tester",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Merge Test Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "character with 0 action values can receive non-zero values", %{campaign: campaign} do
      # Create a character with 0 action values (considered blank for merge)
      {:ok, character} =
        Characters.create_character(%{
          name: "Blank Action Values",
          campaign_id: campaign.id,
          action_values: %{
            "Guns" => 0,
            "Defense" => 0,
            "Toughness" => 0,
            "Type" => "PC"
          }
        })

      # Verify 0 values are stored (these would be overwritten in a merge)
      assert character.action_values["Guns"] == 0
      assert character.action_values["Defense"] == 0
      assert character.action_values["Toughness"] == 0

      # Verify that updating with non-zero values works
      {:ok, updated} =
        Characters.update_character(character, %{
          action_values: Map.merge(character.action_values, %{"Guns" => 15, "Defense" => 14})
        })

      assert updated.action_values["Guns"] == 15
      assert updated.action_values["Defense"] == 14
    end

    test "character with non-zero action values preserves them on update", %{campaign: campaign} do
      # Create a character with real values
      {:ok, character} =
        Characters.create_character(%{
          name: "Has Values",
          campaign_id: campaign.id,
          action_values: %{
            "Guns" => 15,
            "Defense" => 14,
            "Toughness" => 7,
            "Type" => "PC"
          }
        })

      # Verify values are preserved
      assert character.action_values["Guns"] == 15
      assert character.action_values["Defense"] == 14
      assert character.action_values["Toughness"] == 7

      # Verify partial update preserves existing values
      {:ok, updated} =
        Characters.update_character(character, %{
          action_values: %{"Wounds" => 10}
        })

      # Original values should still be there
      assert updated.action_values["Guns"] == 15
      assert updated.action_values["Defense"] == 14
      assert updated.action_values["Wounds"] == 10
    end

    test "character with empty description can receive values", %{campaign: campaign} do
      # Create a character with empty description fields
      {:ok, character} =
        Characters.create_character(%{
          name: "Blank Description",
          campaign_id: campaign.id,
          description: %{
            "Age" => "",
            "Height" => "",
            "Eye Color" => "Blue"
          }
        })

      # Verify blank fields are stored
      assert character.description["Age"] == ""
      assert character.description["Height"] == ""
      assert character.description["Eye Color"] == "Blue"

      # Verify updating works
      {:ok, updated} =
        Characters.update_character(character, %{
          description: Map.merge(character.description, %{"Age" => "35"})
        })

      assert updated.description["Age"] == "35"
      assert updated.description["Eye Color"] == "Blue"
    end

    test "character description preserves existing non-blank values", %{campaign: campaign} do
      # Create a character with real description values
      {:ok, character} =
        Characters.create_character(%{
          name: "Has Description",
          campaign_id: campaign.id,
          description: %{
            "Age" => "35",
            "Height" => "6'2\"",
            "Eye Color" => "Brown",
            "Hair Color" => "Black"
          }
        })

      # Verify values are preserved
      assert character.description["Age"] == "35"
      assert character.description["Height"] == "6'2\""
      assert character.description["Eye Color"] == "Brown"
      assert character.description["Hair Color"] == "Black"
    end
  end
end
