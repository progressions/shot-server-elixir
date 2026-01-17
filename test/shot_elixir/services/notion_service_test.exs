defmodule ShotElixir.Services.NotionServiceTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Services.NotionService
  alias ShotElixir.Characters
  alias ShotElixir.Characters.Character
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Accounts
  alias ShotElixir.Factions
  alias ShotElixir.Junctures
  alias ShotElixir.Parties
  alias ShotElixir.Sites
  alias ShotElixir.Adventures
  alias ShotElixir.Adventures.Adventure
  alias ShotElixir.Notion.NotionSyncLog

  defmodule NotionClientStubSuccess do
    def get_me(_opts), do: %{"id" => "bot-user-id", "object" => "user", "type" => "bot"}

    def get_page(page_id) do
      %{
        "id" => page_id,
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Notion Name"}]},
          "Description" => %{"rich_text" => [%{"plain_text" => "Notion Description"}]},
          "At a Glance" => %{"checkbox" => true}
        },
        "last_edited_by" => %{"id" => "some-other-user-id"}
      }
    end
  end

  defmodule NotionClientStubError do
    def get_me(_opts), do: %{"code" => "error", "message" => "Failed to get user"}

    def get_page(_page_id) do
      %{"code" => "object_not_found", "message" => "Page not found"}
    end
  end

  defmodule NotionClientStubCharacterSuccess do
    def get_me(_opts), do: %{"id" => "bot-user-id", "object" => "user", "type" => "bot"}

    def get_page(page_id) do
      %{
        "id" => page_id,
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Notion Character Name"}]},
          "Type" => %{"select" => %{"name" => "npc"}},
          "Defense" => %{"number" => 14},
          "Toughness" => %{"number" => 7},
          "Speed" => %{"number" => 6}
        },
        "last_edited_by" => %{"id" => "some-other-user-id"}
      }
    end

    def get_blocks(_page_id) do
      %{"results" => []}
    end
  end

  defmodule NotionClientStubCharacterBotEdited do
    def get_me(_opts), do: %{"id" => "bot-user-id", "object" => "user", "type" => "bot"}

    def get_page(page_id) do
      %{
        "id" => page_id,
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Bot Authored Name"}]},
          "Type" => %{"select" => %{"name" => "npc"}},
          "Defense" => %{"number" => 14},
          "Toughness" => %{"number" => 7},
          "Speed" => %{"number" => 6}
        },
        "last_edited_by" => %{"id" => "bot-user-id"}
      }
    end

    def get_blocks(_page_id) do
      %{"results" => []}
    end
  end

  defmodule NotionClientStubCharacterGetMeError do
    def get_me(_opts), do: %{"code" => "error", "message" => "Failed to get user"}

    def get_page(page_id) do
      %{
        "id" => page_id,
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Fallback Notion Name"}]},
          "Description" => %{"rich_text" => [%{"plain_text" => "Fallback description"}]},
          "At a Glance" => %{"checkbox" => true},
          "Type" => %{"select" => %{"name" => "npc"}},
          "Defense" => %{"number" => 14},
          "Toughness" => %{"number" => 7},
          "Speed" => %{"number" => 6}
        },
        "last_edited_by" => %{"id" => "bot-user-id"}
      }
    end

    def get_blocks(_page_id) do
      %{"results" => []}
    end
  end

  defmodule NotionClientStubJunctureSuccess do
    def get_me(_opts), do: %{"id" => "bot-user-id", "object" => "user", "type" => "bot"}

    def character_notion_id, do: "c0a80123-4567-489a-bcde-1234567890ab"
    def site_notion_id, do: "e5b1b80e-2a50-4a43-92b1-8d1f5f4dd721"

    def get_page(page_id) do
      %{
        "id" => page_id,
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Notion Name"}]},
          "Description" => %{"rich_text" => [%{"plain_text" => "Notion Description"}]},
          "At a Glance" => %{"checkbox" => true},
          "People" => %{"relation" => [%{"id" => character_notion_id()}]},
          "Locations" => %{"relation" => [%{"id" => site_notion_id()}]}
        },
        "last_edited_by" => %{"id" => "some-other-user-id"}
      }
    end
  end

  defmodule NotionClientStubDataSource do
    def get_me(_opts), do: %{"id" => "bot-user-id", "object" => "user", "type" => "bot"}

    # Now find_pages_in_database uses the ID directly as a data_source_id,
    # so we just need to stub data_source_query
    def data_source_query("ds-id-success", _filter) do
      %{
        "results" => [
          %{
            "id" => "page-1",
            "properties" => %{
              "Name" => %{"title" => [%{"plain_text" => "Alpha"}]}
            },
            "url" => "https://notion.example/page-1"
          }
        ]
      }
    end
  end

  defmodule NotionClientStubDataSourceMissing do
    def get_me(_opts), do: %{"id" => "bot-user-id", "object" => "user", "type" => "bot"}

    # Stub that returns an error from data_source_query
    def data_source_query("ds-id-missing", _filter) do
      %{"code" => "object_not_found", "message" => "Data source not found"}
    end
  end

  defmodule NotionClientStubSiteBotEdited do
    def get_me(_opts), do: %{"id" => "bot-user-id", "object" => "user", "type" => "bot"}

    def get_page(page_id) do
      %{
        "id" => page_id,
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Bot Authored Site"}]},
          "Description" => %{"rich_text" => [%{"plain_text" => "Bot Description"}]},
          "At a Glance" => %{"checkbox" => true}
        },
        "last_edited_by" => %{"id" => "bot-user-id"}
      }
    end
  end

  defmodule NotionClientStubSiteGetMeError do
    def get_me(_opts), do: %{"code" => "error", "message" => "Failed to get user"}

    def get_page(page_id) do
      %{
        "id" => page_id,
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Fail-open Site"}]},
          "Description" => %{"rich_text" => [%{"plain_text" => "Site Desc"}]},
          "At a Glance" => %{"checkbox" => true}
        },
        "last_edited_by" => %{"id" => "bot-user-id"}
      }
    end
  end

  defmodule NotionClientStubAdventureBotEdited do
    def get_me(_opts), do: %{"id" => "bot-user-id", "object" => "user", "type" => "bot"}

    def get_page(page_id) do
      %{
        "id" => page_id,
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Bot Adventure"}]},
          "Description" => %{"rich_text" => [%{"plain_text" => "Adventure Desc"}]},
          "At a Glance" => %{"checkbox" => true}
        },
        "last_edited_by" => %{"id" => "bot-user-id"}
      }
    end
  end

  defmodule NotionClientStubAdventureGetMeError do
    def get_me(_opts), do: %{"code" => "error", "message" => "Failed to get user"}

    def get_page(page_id) do
      %{
        "id" => page_id,
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Fail-open Adventure"}]},
          "Description" => %{"rich_text" => [%{"plain_text" => "Adventure Desc"}]},
          "At a Glance" => %{"checkbox" => true}
        },
        "last_edited_by" => %{"id" => "bot-user-id"}
      }
    end
  end

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

  describe "update entity from notion logging" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-entity-notion@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Notion Entity Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, site} =
        Sites.create_site(%{
          name: "Local Site",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      {:ok, party} =
        Parties.create_party(%{
          name: "Local Party",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      {:ok, faction} =
        Factions.create_faction(%{
          name: "Local Faction",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      {:ok, juncture} =
        Junctures.create_juncture(%{
          name: "Local Juncture",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Local Character",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      {:ok, adventure} =
        Adventures.create_adventure(%{
          name: "Local Adventure",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      {:ok,
       site: site,
       party: party,
       faction: faction,
       juncture: juncture,
       character: character,
       adventure: adventure,
       campaign: campaign}
    end

    test "update_site_from_notion logs success and updates attributes", %{site: site} do
      {:ok, updated_site} =
        NotionService.update_site_from_notion(site, client: NotionClientStubSuccess)

      assert updated_site.name == "Notion Name"
      assert updated_site.description == "<p>Notion Description</p>"
      assert updated_site.at_a_glance == true

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "site", entity_id: ^site.id)
        |> Repo.all()

      assert log.status == "success"
      assert log.payload["page_id"] == site.notion_page_id
    end

    test "update_site_from_notion logs errors from Notion API", %{site: site} do
      assert {:error, {:notion_api_error, "object_not_found", "Page not found"}} =
               NotionService.update_site_from_notion(site, client: NotionClientStubError)

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "site", entity_id: ^site.id)
        |> Repo.all()

      assert log.status == "error"
      assert String.contains?(log.error_message, "Notion API error")
    end

    test "skips site update when page was last edited by the bot", %{site: site} do
      {:ok, returned_site} =
        NotionService.update_site_from_notion(site, client: NotionClientStubSiteBotEdited)

      reloaded = Sites.get_site(site.id)
      assert returned_site.id == site.id
      assert reloaded.description == site.description
    end

    test "continues site update when bot user lookup fails (fail-open)", %{site: site} do
      {:ok, updated_site} =
        NotionService.update_site_from_notion(site,
          client: NotionClientStubSiteGetMeError,
          token: "fail-open-token"
        )

      assert updated_site.description == "<p>Site Desc</p>"
    end

    test "update_party_from_notion logs success and updates attributes", %{party: party} do
      {:ok, updated_party} =
        NotionService.update_party_from_notion(party, client: NotionClientStubSuccess)

      assert updated_party.name == "Notion Name"
      assert updated_party.description == "<p>Notion Description</p>"
      assert updated_party.at_a_glance == true

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "party", entity_id: ^party.id)
        |> Repo.all()

      assert log.status == "success"
      assert log.payload["page_id"] == party.notion_page_id
    end

    test "update_party_from_notion logs errors from Notion API", %{party: party} do
      assert {:error, {:notion_api_error, "object_not_found", "Page not found"}} =
               NotionService.update_party_from_notion(party, client: NotionClientStubError)

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "party", entity_id: ^party.id)
        |> Repo.all()

      assert log.status == "error"
      assert String.contains?(log.error_message, "Notion API error")
    end

    test "update_faction_from_notion logs success and updates attributes", %{faction: faction} do
      {:ok, updated_faction} =
        NotionService.update_faction_from_notion(faction, client: NotionClientStubSuccess)

      assert updated_faction.name == "Notion Name"
      assert updated_faction.description == "<p>Notion Description</p>"
      assert updated_faction.at_a_glance == true

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "faction", entity_id: ^faction.id)
        |> Repo.all()

      assert log.status == "success"
      assert log.payload["page_id"] == faction.notion_page_id
    end

    test "update_faction_from_notion logs errors from Notion API", %{faction: faction} do
      assert {:error, {:notion_api_error, "object_not_found", "Page not found"}} =
               NotionService.update_faction_from_notion(faction, client: NotionClientStubError)

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "faction", entity_id: ^faction.id)
        |> Repo.all()

      assert log.status == "error"
      assert String.contains?(log.error_message, "Notion API error")
    end

    test "update_juncture_from_notion logs success and updates attributes", %{
      juncture: juncture,
      campaign: campaign
    } do
      {:ok, character} =
        Characters.create_character(%{
          name: "Notion Character",
          campaign_id: campaign.id,
          notion_page_id: NotionClientStubJunctureSuccess.character_notion_id()
        })

      {:ok, site} =
        Sites.create_site(%{
          name: "Notion Site",
          campaign_id: campaign.id,
          notion_page_id: NotionClientStubJunctureSuccess.site_notion_id()
        })

      {:ok, updated_juncture} =
        NotionService.update_juncture_from_notion(juncture,
          client: NotionClientStubJunctureSuccess
        )

      assert updated_juncture.name == "Notion Name"
      assert updated_juncture.description == "<p>Notion Description</p>"
      assert updated_juncture.at_a_glance == true

      updated_character = Repo.get(Character, character.id)
      assert updated_character.juncture_id == juncture.id

      updated_site = Sites.get_site(site.id)
      assert updated_site.juncture_id == juncture.id

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "juncture", entity_id: ^juncture.id)
        |> Repo.all()

      assert log.status == "success"
      assert log.payload["page_id"] == juncture.notion_page_id
    end

    test "update_juncture_from_notion logs errors from Notion API", %{juncture: juncture} do
      assert {:error, {:notion_api_error, "object_not_found", "Page not found"}} =
               NotionService.update_juncture_from_notion(juncture, client: NotionClientStubError)

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "juncture", entity_id: ^juncture.id)
        |> Repo.all()

      assert log.status == "error"
      assert String.contains?(log.error_message, "Notion API error")
    end

    test "update_character_from_notion logs success and updates attributes", %{
      character: character
    } do
      {:ok, updated_character} =
        NotionService.update_character_from_notion(character,
          client: NotionClientStubCharacterSuccess
        )

      assert updated_character.name == "Notion Character Name"

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "character", entity_id: ^character.id)
        |> Repo.all()

      assert log.status == "success"
      assert log.payload["page_id"] == character.notion_page_id
    end

    test "update_character_from_notion logs errors from Notion API", %{character: character} do
      assert {:error, {:notion_api_error, "object_not_found", "Page not found"}} =
               NotionService.update_character_from_notion(character,
                 client: NotionClientStubError
               )

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "character", entity_id: ^character.id)
        |> Repo.all()

      assert log.status == "error"
      assert String.contains?(log.error_message, "Notion API error")
    end

    test "skips character update when page was last edited by the bot", %{character: character} do
      original_name = character.name

      assert {:ok, returned_character} =
               NotionService.update_character_from_notion(character,
                 client: NotionClientStubCharacterBotEdited
               )

      reloaded = Repo.get(Character, character.id)
      assert returned_character.id == character.id
      assert reloaded.name == original_name

      logs =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "character", entity_id: ^character.id)
        |> Repo.all()

      assert logs == []
    end

    test "continues character update when bot user lookup fails (fail-open)", %{
      character: character
    } do
      {:ok, updated_character} =
        NotionService.update_character_from_notion(character,
          client: NotionClientStubCharacterGetMeError,
          token: "fail-open-token"
        )

      assert updated_character.name == "Fallback Notion Name"

      [log] =
        NotionSyncLog
        |> Ecto.Query.where(entity_type: "character", entity_id: ^character.id)
        |> Repo.all()

      assert log.status == "success"
    end

    test "update_adventure_from_notion logs success and updates attributes", %{
      adventure: adventure
    } do
      {:ok, updated_adventure} =
        NotionService.update_adventure_from_notion(adventure, client: NotionClientStubSuccess)

      assert updated_adventure.name == "Notion Name"
      assert updated_adventure.description == "<p>Notion Description</p>"
      assert updated_adventure.at_a_glance == true
    end

    test "update_adventure_from_notion logs errors from Notion API", %{adventure: adventure} do
      assert {:error, {:notion_api_error, "object_not_found", "Page not found"}} =
               NotionService.update_adventure_from_notion(adventure,
                 client: NotionClientStubError
               )
    end

    test "skips adventure update when page was last edited by the bot", %{adventure: adventure} do
      {:ok, returned_adventure} =
        NotionService.update_adventure_from_notion(adventure,
          client: NotionClientStubAdventureBotEdited
        )

      reloaded = Repo.get(Adventure, adventure.id)
      assert returned_adventure.id == adventure.id
      assert reloaded.description == adventure.description
    end

    test "continues adventure update when bot user lookup fails (fail-open)", %{
      adventure: adventure
    } do
      {:ok, updated_adventure} =
        NotionService.update_adventure_from_notion(adventure,
          client: NotionClientStubAdventureGetMeError,
          token: "fail-open-token"
        )

      assert updated_adventure.description == "<p>Adventure Desc</p>"
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

  describe "find_pages_in_database/3" do
    test "returns pages when data_source_query succeeds" do
      results =
        NotionService.find_pages_in_database("ds-id-success", "Alpha",
          client: NotionClientStubDataSource
        )

      assert [
               %{"id" => "page-1", "title" => "Alpha", "url" => "https://notion.example/page-1"}
             ] = results
    end

    test "returns empty list when data_source_query fails" do
      results =
        NotionService.find_pages_in_database("ds-id-missing", "Alpha",
          client: NotionClientStubDataSourceMissing
        )

      assert [] = results
    end
  end

  describe "find_image_block/1 pagination" do
    defmodule NotionClientStubImageFirstPage do
      @moduledoc "Stub that returns an image on the first page"
      def get_block_children(_page_id, _opts \\ %{}) do
        %{
          "results" => [
            %{"type" => "paragraph", "id" => "block-1"},
            %{"type" => "image", "id" => "image-block-1"},
            %{"type" => "paragraph", "id" => "block-2"}
          ],
          "has_more" => false,
          "next_cursor" => nil
        }
      end
    end

    defmodule NotionClientStubImageSecondPage do
      @moduledoc "Stub that returns an image on the second page (after pagination)"
      def get_block_children(_page_id, opts \\ %{}) do
        case Map.get(opts, :start_cursor) do
          nil ->
            # First page - no image
            %{
              "results" => [
                %{"type" => "paragraph", "id" => "block-1"},
                %{"type" => "heading_1", "id" => "block-2"},
                %{"type" => "paragraph", "id" => "block-3"}
              ],
              "has_more" => true,
              "next_cursor" => "cursor-page-2"
            }

          "cursor-page-2" ->
            # Second page - has image
            %{
              "results" => [
                %{"type" => "paragraph", "id" => "block-4"},
                %{"type" => "image", "id" => "image-block-on-page-2"},
                %{"type" => "paragraph", "id" => "block-5"}
              ],
              "has_more" => false,
              "next_cursor" => nil
            }
        end
      end
    end

    defmodule NotionClientStubNoImage do
      @moduledoc "Stub that returns multiple pages with no image"
      def get_block_children(_page_id, opts \\ %{}) do
        case Map.get(opts, :start_cursor) do
          nil ->
            %{
              "results" => [
                %{"type" => "paragraph", "id" => "block-1"},
                %{"type" => "heading_1", "id" => "block-2"}
              ],
              "has_more" => true,
              "next_cursor" => "cursor-page-2"
            }

          "cursor-page-2" ->
            %{
              "results" => [
                %{"type" => "paragraph", "id" => "block-3"},
                %{"type" => "callout", "id" => "block-4"}
              ],
              "has_more" => false,
              "next_cursor" => nil
            }
        end
      end
    end

    defmodule NotionClientStubEmptyResults do
      @moduledoc "Stub that returns empty results"
      def get_block_children(_page_id, _opts \\ %{}) do
        %{
          "results" => [],
          "has_more" => false,
          "next_cursor" => nil
        }
      end
    end

    test "finds image on first page without pagination" do
      page = %{"id" => "test-page-id"}

      result =
        NotionService.find_image_block(page, client: NotionClientStubImageFirstPage)

      assert %{"type" => "image", "id" => "image-block-1"} = result
    end

    test "finds image on second page via pagination" do
      page = %{"id" => "test-page-id"}

      result =
        NotionService.find_image_block(page, client: NotionClientStubImageSecondPage)

      assert %{"type" => "image", "id" => "image-block-on-page-2"} = result
    end

    test "returns nil when no image found after checking all pages" do
      page = %{"id" => "test-page-id"}

      result = NotionService.find_image_block(page, client: NotionClientStubNoImage)

      assert result == nil
    end

    test "returns nil for empty results" do
      page = %{"id" => "test-page-id"}

      result = NotionService.find_image_block(page, client: NotionClientStubEmptyResults)

      assert result == nil
    end
  end
end
