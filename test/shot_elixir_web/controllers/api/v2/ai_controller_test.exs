defmodule ShotElixirWeb.Api.V2.AiControllerTest do
  @moduledoc """
  Tests for the AI Controller extend endpoint.

  Tests cover:
  - Setting extending flag when job is enqueued
  - Returning conflict error when extending is already true
  - Authorization checks for the extend endpoint
  - Error handling for database update failures
  """
  use ShotElixirWeb.ConnCase, async: true
  use Oban.Testing, repo: ShotElixir.Repo

  alias ShotElixir.{
    Characters,
    Campaigns,
    Accounts
  }

  alias ShotElixir.Guardian
  alias ShotElixir.Workers.AiCharacterUpdateWorker

  setup %{conn: conn} do
    {:ok, gamemaster} =
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
        last_name: "One",
        gamemaster: false
      })

    {:ok, other_user} =
      Accounts.create_user(%{
        email: "other@example.com",
        password: "password123",
        first_name: "Other",
        last_name: "User",
        gamemaster: false
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Test campaign for AI",
        user_id: gamemaster.id
      })

    {:ok, other_campaign} =
      Campaigns.create_campaign(%{
        name: "Other Campaign",
        description: "Another campaign",
        user_id: other_user.id
      })

    # Set campaign as current for users
    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)
    {:ok, player_with_campaign} = Accounts.set_current_campaign(player, campaign.id)
    {:ok, other_with_campaign} = Accounts.set_current_campaign(other_user, other_campaign.id)

    # Add player to campaign
    {:ok, _} = Campaigns.add_member(campaign, player)

    # Create a test character
    {:ok, character} =
      Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id,
        user_id: gm_with_campaign.id,
        action_values: %{"Type" => "PC", "Archetype" => "Everyday Hero"},
        extending: false
      })

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gm_with_campaign,
     player: player_with_campaign,
     other_user: other_with_campaign,
     campaign: campaign,
     other_campaign: other_campaign,
     character: character}
  end

  describe "extend" do
    test "returns accepted status and enqueues job", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      # Use manual mode to prevent the job from actually running during tests
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, token, _claims} = Guardian.encode_and_sign(gm)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(~p"/api/v2/ai/#{character.id}/extend")

        assert json_response(conn, 202) == %{"message" => "Character AI update in progress"}

        # Verify extending flag was set
        updated_character = Characters.get_character(character.id)
        assert updated_character.extending == true

        # Verify job was enqueued
        assert_enqueued(worker: AiCharacterUpdateWorker, args: %{character_id: character.id})
      end)
    end

    test "returns conflict when character is already extending", %{
      conn: conn,
      gamemaster: gm,
      character: character
    } do
      # Set extending flag
      {:ok, _} = Characters.update_character(character, %{extending: true})

      {:ok, token, _claims} = Guardian.encode_and_sign(gm)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v2/ai/#{character.id}/extend")

      assert json_response(conn, 409) == %{"error" => "Character extension already in progress"}

      # Verify no job was enqueued
      refute_enqueued(worker: AiCharacterUpdateWorker)
    end

    test "returns 404 for non-existent character", %{conn: conn, gamemaster: gm} do
      {:ok, token, _claims} = Guardian.encode_and_sign(gm)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v2/ai/#{Ecto.UUID.generate()}/extend")

      assert json_response(conn, 404) == %{"error" => "Character not found"}
    end

    test "returns 404 for character in different campaign", %{
      conn: conn,
      gamemaster: gm,
      other_campaign: other_campaign,
      other_user: other_user
    } do
      # Create character in other campaign
      {:ok, other_character} =
        Characters.create_character(%{
          name: "Other Character",
          campaign_id: other_campaign.id,
          user_id: other_user.id,
          action_values: %{"Type" => "PC"}
        })

      {:ok, token, _claims} = Guardian.encode_and_sign(gm)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v2/ai/#{other_character.id}/extend")

      assert json_response(conn, 404) == %{"error" => "Character not found"}
    end

    test "returns 422 when no active campaign selected", %{conn: conn, gamemaster: gm} do
      # Clear current campaign
      {:ok, gm_no_campaign} = Accounts.set_current_campaign(gm, nil)

      {:ok, token, _claims} = Guardian.encode_and_sign(gm_no_campaign)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v2/ai/#{Ecto.UUID.generate()}/extend")

      assert json_response(conn, 422) == %{"error" => "No active campaign selected"}
    end

    test "allows campaign member to extend character", %{
      conn: conn,
      player: player,
      character: character
    } do
      # Use manual mode to prevent the job from actually running during tests
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, token, _claims} = Guardian.encode_and_sign(player)

        conn =
          conn
          |> put_req_header("authorization", "Bearer #{token}")
          |> post(~p"/api/v2/ai/#{character.id}/extend")

        assert json_response(conn, 202) == %{"message" => "Character AI update in progress"}
      end)
    end

    test "denies access to non-member of campaign", %{
      conn: conn,
      other_user: other_user,
      character: character,
      campaign: campaign
    } do
      # Set other_user's current campaign to the test campaign (but they're not a member)
      {:ok, other_with_test_campaign} = Accounts.set_current_campaign(other_user, campaign.id)

      {:ok, token, _claims} = Guardian.encode_and_sign(other_with_test_campaign)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v2/ai/#{character.id}/extend")

      assert json_response(conn, 403) == %{"error" => "Access denied"}
    end

    test "returns 401 when not authenticated", %{conn: conn, character: character} do
      conn = post(conn, ~p"/api/v2/ai/#{character.id}/extend")

      assert json_response(conn, 401)
    end
  end
end
