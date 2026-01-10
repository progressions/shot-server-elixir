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
end
