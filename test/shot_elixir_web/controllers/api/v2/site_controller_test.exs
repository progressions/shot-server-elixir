defmodule ShotElixirWeb.Api.V2.SiteControllerTest do
  use ShotElixirWeb.ConnCase, async: true
  alias ShotElixir.{Campaigns, Sites, Factions, Junctures, Characters, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    # Create gamemaster user
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm@test.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    # Create a campaign
    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Site Test Campaign",
        description: "Campaign for site testing",
        user_id: gamemaster.id
      })

    # Set current campaign for gamemaster
    {:ok, gamemaster} = Accounts.update_user(gamemaster, %{current_campaign_id: campaign.id})

    {:ok, faction} =
      Factions.create_faction(%{
        name: "Test Faction",
        campaign_id: campaign.id
      })

    {:ok, juncture} =
      Junctures.create_juncture(%{
        name: "Contemporary",
        campaign_id: campaign.id
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> authenticate(gamemaster)

    %{
      conn: conn,
      user: gamemaster,
      campaign: campaign,
      faction: faction,
      juncture: juncture
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "index" do
    test "lists all sites for campaign", %{conn: conn, campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Temple of Doom",
          campaign_id: campaign.id,
          description: "A dangerous temple"
        })

      conn = get(conn, ~p"/api/v2/sites")
      assert %{"sites" => [returned_site]} = json_response(conn, 200)
      assert returned_site["id"] == site.id
      assert returned_site["name"] == "Temple of Doom"
    end

    test "returns empty list when no sites", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/sites")
      assert %{"sites" => []} = json_response(conn, 200)
    end

    test "includes string ids for sites and factions", %{
      conn: conn,
      campaign: campaign,
      faction: faction,
      user: user
    } do
      {:ok, _site} =
        Sites.create_site(%{
          name: "Encoded Site",
          campaign_id: campaign.id,
          faction_id: faction.id
        })

      conn = get(conn, ~p"/api/v2/sites", %{user_id: user.id})
      payload = json_response(conn, 200)

      assert Jason.encode!(payload)
      assert Enum.all?(payload["sites"], &is_binary(&1["id"]))
      assert Enum.all?(payload["factions"], &is_binary(&1["id"]))
      assert is_map(payload["meta"])
    end

    test "returns error when no campaign selected", %{conn: conn, user: user} do
      {:ok, user_without_campaign} = Accounts.update_user(user, %{current_campaign_id: nil})

      conn =
        conn
        |> authenticate(user_without_campaign)
        |> get(~p"/api/v2/sites")

      assert %{"error" => "No active campaign selected"} = json_response(conn, 422)
    end
  end

  describe "show" do
    setup %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Temple of Doom",
          campaign_id: campaign.id,
          description: "A dangerous temple"
        })

      %{site: site}
    end

    test "returns site when found", %{conn: conn, site: site} do
      conn = get(conn, ~p"/api/v2/sites/#{site.id}")
      assert returned_site = json_response(conn, 200)
      assert returned_site["id"] == site.id
      assert returned_site["name"] == "Temple of Doom"
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/sites/#{Ecto.UUID.generate()}")
      assert %{"error" => "Site not found"} = json_response(conn, 404)
    end

    test "includes attunements in show response", %{conn: conn, site: site, campaign: campaign} do
      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id
        })

      {:ok, _attunement} =
        Sites.create_attunement(%{
          site_id: site.id,
          character_id: character.id
        })

      conn = get(conn, ~p"/api/v2/sites/#{site.id}")
      assert returned_site = json_response(conn, 200)

      assert [%{"character_id" => character_id, "character" => attuned_character}] =
               returned_site["attunements"]

      assert character_id == character.id
      assert attuned_character["name"] == "Test Character"
    end
  end

  describe "create" do
    test "creates site with valid data", %{
      conn: conn,
      campaign: campaign,
      faction: faction,
      juncture: juncture
    } do
      site_params = %{
        "name" => "Lost Temple",
        "description" => "An ancient ruin",
        "faction_id" => faction.id,
        "juncture_id" => juncture.id
      }

      conn = post(conn, ~p"/api/v2/sites", site: site_params)
      assert site = json_response(conn, 201)
      assert site["name"] == "Lost Temple"
      assert site["description"] == "An ancient ruin"
      assert site["campaign_id"] == campaign.id
      assert site["faction"]["name"] == "Test Faction"
      assert site["juncture"]["name"] == "Contemporary"
    end

    test "returns error with invalid data", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/sites", site: %{})
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["name"] != nil
    end
  end

  describe "update" do
    setup %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Temple",
          campaign_id: campaign.id
        })

      %{site: site}
    end

    test "updates site with valid data", %{conn: conn, site: site, faction: faction} do
      conn =
        patch(conn, ~p"/api/v2/sites/#{site.id}",
          site: %{
            "name" => "Updated Temple",
            "description" => "New description",
            "faction_id" => faction.id
          }
        )

      assert updated_site = json_response(conn, 200)
      assert updated_site["name"] == "Updated Temple"
      assert updated_site["description"] == "New description"
      assert updated_site["faction"]["name"] == "Test Faction"
    end

    test "returns error with invalid data", %{conn: conn, site: site} do
      conn = patch(conn, ~p"/api/v2/sites/#{site.id}", site: %{"name" => ""})
      assert %{"errors" => errors} = json_response(conn, 422)
      assert errors["name"] != nil
    end

    test "returns 404 when site not found", %{conn: conn} do
      conn = patch(conn, ~p"/api/v2/sites/#{Ecto.UUID.generate()}", site: %{"name" => "Test"})
      assert %{"error" => "Site not found"} = json_response(conn, 404)
    end
  end

  describe "delete" do
    setup %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Temple",
          campaign_id: campaign.id
        })

      %{site: site}
    end

    test "hard deletes the site", %{conn: conn, site: site} do
      conn = delete(conn, ~p"/api/v2/sites/#{site.id}")
      assert response(conn, 204)

      # Site should be completely removed from database
      assert Sites.get_site(site.id) == nil
    end

    test "returns 404 when site not found", %{conn: conn} do
      conn = delete(conn, ~p"/api/v2/sites/#{Ecto.UUID.generate()}")
      assert %{"error" => "Site not found"} = json_response(conn, 404)
    end
  end

  describe "attune" do
    setup %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Temple",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id
        })

      %{site: site, character: character}
    end

    test "creates attunement between character and site", %{
      conn: conn,
      site: site,
      character: character
    } do
      conn = post(conn, ~p"/api/v2/sites/#{site.id}/attune", character_id: character.id)
      assert returned_site = json_response(conn, 200)
      assert [attunement] = returned_site["attunements"]
      assert attunement["character_id"] == character.id
    end

    test "returns error when site not found", %{conn: conn, character: character} do
      conn =
        post(conn, ~p"/api/v2/sites/#{Ecto.UUID.generate()}/attune", character_id: character.id)

      assert %{"error" => "Site not found"} = json_response(conn, 404)
    end

    test "returns error for duplicate attunement", %{conn: conn, site: site, character: character} do
      {:ok, _} = Sites.create_attunement(%{site_id: site.id, character_id: character.id})
      conn = post(conn, ~p"/api/v2/sites/#{site.id}/attune", character_id: character.id)
      assert %{"errors" => _} = json_response(conn, 422)
    end
  end

  describe "unattune" do
    setup %{campaign: campaign} do
      {:ok, site} =
        Sites.create_site(%{
          name: "Temple",
          campaign_id: campaign.id
        })

      {:ok, character} =
        Characters.create_character(%{
          name: "Test Character",
          campaign_id: campaign.id
        })

      {:ok, attunement} =
        Sites.create_attunement(%{
          site_id: site.id,
          character_id: character.id
        })

      %{site: site, character: character, attunement: attunement}
    end

    test "removes attunement between character and site", %{
      conn: conn,
      site: site,
      character: character
    } do
      conn = delete(conn, ~p"/api/v2/sites/#{site.id}/attune/#{character.id}")
      assert response(conn, 204)

      attunement = Sites.get_attunement_by_character_and_site(character.id, site.id)
      assert attunement == nil
    end

    test "returns 404 when attunement not found", %{conn: conn, site: site} do
      conn = delete(conn, ~p"/api/v2/sites/#{site.id}/attune/#{Ecto.UUID.generate()}")
      assert %{"error" => "Attunement not found"} = json_response(conn, 404)
    end
  end
end
