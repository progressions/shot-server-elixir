defmodule ShotElixirWeb.Api.V2.AiImageControllerTest do
  @moduledoc """
  Tests for the AI Image Controller.

  Tests cover:
  - AI generation toggle enforcement for create and attach actions
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{
    Characters,
    Campaigns,
    Accounts
  }

  alias ShotElixir.Guardian

  setup %{conn: conn} do
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "gm@example.com",
        password: "password123",
        first_name: "Game",
        last_name: "Master",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Test campaign for AI images",
        user_id: gamemaster.id
      })

    # Set campaign as current for gamemaster
    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)

    # Create a test character
    {:ok, character} =
      Characters.create_character(%{
        name: "Test Character",
        campaign_id: campaign.id,
        user_id: gm_with_campaign.id,
        action_values: %{"Type" => "PC", "Archetype" => "Everyday Hero"}
      })

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gm_with_campaign,
     campaign: campaign,
     character: character}
  end

  describe "create" do
    test "returns 403 when AI generation is disabled for campaign", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign,
      character: character
    } do
      # Disable AI generation for the campaign
      {:ok, _} = Campaigns.update_campaign(campaign, %{ai_generation_enabled: false})

      {:ok, token, _claims} = Guardian.encode_and_sign(gm)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v2/ai_images", %{
          "entity_type" => "Character",
          "entity_id" => character.id,
          "prompt" => "A heroic warrior"
        })

      assert json_response(conn, 403) == %{
               "error" => "AI generation is disabled for this campaign"
             }
    end
  end

  describe "attach" do
    test "returns 403 when AI generation is disabled for campaign", %{
      conn: conn,
      gamemaster: gm,
      campaign: campaign,
      character: character
    } do
      # Disable AI generation for the campaign
      {:ok, _} = Campaigns.update_campaign(campaign, %{ai_generation_enabled: false})

      {:ok, token, _claims} = Guardian.encode_and_sign(gm)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v2/ai_images/attach", %{
          "entity_type" => "Character",
          "entity_id" => character.id,
          "image_url" => "https://example.com/image.png"
        })

      assert json_response(conn, 403) == %{
               "error" => "AI generation is disabled for this campaign"
             }
    end
  end
end
