defmodule ShotElixirWeb.Api.V2.EncounterControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{Accounts, Campaigns, Characters, Fights, Vehicles, Repo}
  alias ShotElixir.Fights.Shot
  alias ShotElixir.Guardian
  import Ecto.Query

  setup %{conn: conn} do
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm-encounter@test.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Encounter Campaign",
        description: "Campaign for encounter tests",
        user_id: gamemaster.id
      })

    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)

    conn = put_req_header(conn, "accept", "application/json")

    %{
      conn: conn,
      gamemaster: gm_with_campaign,
      campaign: campaign
    }
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  test "show preserves duplicate character_ids for encounters", %{
    conn: conn,
    gamemaster: gm,
    campaign: campaign
  } do
    {:ok, character} =
      Characters.create_character(%{
        name: "Assassin",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "Mook"}
      })

    {:ok, fight} =
      Fights.create_fight(%{
        name: "Duplicate Assassin Fight",
        campaign_id: campaign.id
      })

    {:ok, _fight} =
      Fights.update_fight(fight, %{
        "character_ids" => [character.id, character.id]
      })

    conn = authenticate(conn, gm)
    conn = get(conn, ~p"/api/v2/encounters/#{fight.id}")
    response = json_response(conn, 200)

    character_ids = response["character_ids"]
    assert length(character_ids) == 2
    assert Enum.frequencies(character_ids) == %{character.id => 2}

    characters_in_shots =
      response["shots"]
      |> Enum.flat_map(fn shot -> shot["characters"] || [] end)

    assert length(characters_in_shots) == 2
    assert Enum.all?(characters_in_shots, fn char -> char["id"] == character.id end)
  end

  test "show returns shot.color with fallback to character.color", %{
    conn: conn,
    gamemaster: gm,
    campaign: campaign
  } do
    # Character with a color set
    {:ok, char_with_color} =
      Characters.create_character(%{
        name: "Character With Color",
        campaign_id: campaign.id,
        user_id: gm.id,
        color: "#ff0000",
        action_values: %{"Type" => "PC"}
      })

    # Character without a color
    {:ok, char_no_color} =
      Characters.create_character(%{
        name: "Character No Color",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "PC"}
      })

    {:ok, fight} =
      Fights.create_fight(%{
        name: "Color Test Fight",
        campaign_id: campaign.id
      })

    {:ok, _fight} =
      Fights.update_fight(fight, %{
        "character_ids" => [char_with_color.id, char_no_color.id]
      })

    # Get the shot for the character with color and set a different shot-specific color
    shot_with_override =
      Repo.one(
        from s in Shot,
          where: s.fight_id == ^fight.id and s.character_id == ^char_with_color.id
      )

    {:ok, _} = Fights.update_shot(shot_with_override, %{"color" => "#00ff00"})

    conn = authenticate(conn, gm)
    conn = get(conn, ~p"/api/v2/encounters/#{fight.id}")
    response = json_response(conn, 200)

    characters =
      response["shots"]
      |> Enum.flat_map(fn shot -> shot["characters"] || [] end)

    # Character with shot-specific color should use shot.color
    char_with_override = Enum.find(characters, fn c -> c["id"] == char_with_color.id end)
    assert char_with_override["color"] == "#00ff00"

    # Character without shot-specific color should fall back to character.color (nil in this case)
    char_without_color = Enum.find(characters, fn c -> c["id"] == char_no_color.id end)
    assert char_without_color["color"] == nil
  end

  test "show falls back to character.color when shot.color is nil", %{
    conn: conn,
    gamemaster: gm,
    campaign: campaign
  } do
    {:ok, character} =
      Characters.create_character(%{
        name: "Character With Base Color",
        campaign_id: campaign.id,
        user_id: gm.id,
        color: "#ff5500",
        action_values: %{"Type" => "PC"}
      })

    {:ok, fight} =
      Fights.create_fight(%{
        name: "Fallback Color Test Fight",
        campaign_id: campaign.id
      })

    {:ok, _fight} =
      Fights.update_fight(fight, %{
        "character_ids" => [character.id]
      })

    # Don't set shot.color - it should fall back to character.color

    conn = authenticate(conn, gm)
    conn = get(conn, ~p"/api/v2/encounters/#{fight.id}")
    response = json_response(conn, 200)

    characters =
      response["shots"]
      |> Enum.flat_map(fn shot -> shot["characters"] || [] end)

    char_response = Enum.find(characters, fn c -> c["id"] == character.id end)
    # Should fall back to character.color since shot.color is nil
    assert char_response["color"] == "#ff5500"
  end

  test "show includes driver details for vehicles", %{
    conn: conn,
    gamemaster: gm,
    campaign: campaign
  } do
    {:ok, driver} =
      Characters.create_character(%{
        name: "Driver Bruce",
        campaign_id: campaign.id,
        user_id: gm.id,
        action_values: %{"Type" => "PC"}
      })

    {:ok, vehicle} =
      Vehicles.create_vehicle(%{
        name: "Stunt Car",
        action_values: %{},
        campaign_id: campaign.id,
        user_id: gm.id
      })

    {:ok, fight} =
      Fights.create_fight(%{
        name: "Driver Test Fight",
        campaign_id: campaign.id
      })

    {:ok, _fight} =
      Fights.update_fight(fight, %{
        "character_ids" => [driver.id],
        "vehicle_ids" => [vehicle.id]
      })

    driver_shot =
      Repo.one(
        from s in Shot,
          where: s.fight_id == ^fight.id and s.character_id == ^driver.id
      )

    vehicle_shot =
      Repo.one(
        from s in Shot,
          where: s.fight_id == ^fight.id and s.vehicle_id == ^vehicle.id
      )

    {:ok, _updated_shot} =
      Fights.update_shot(vehicle_shot, %{
        "driver_id" => driver_shot.id
      })

    conn = authenticate(conn, gm)
    conn = get(conn, ~p"/api/v2/encounters/#{fight.id}")
    response = json_response(conn, 200)

    vehicles =
      response["shots"]
      |> Enum.flat_map(fn shot -> shot["vehicles"] || [] end)

    assert length(vehicles) == 1
    vehicle_payload = List.first(vehicles)

    assert vehicle_payload["driver"]["id"] == driver.id
    assert vehicle_payload["driver"]["shot_id"] == driver_shot.id
    assert vehicle_payload["driver"]["name"] == driver.name
  end
end
