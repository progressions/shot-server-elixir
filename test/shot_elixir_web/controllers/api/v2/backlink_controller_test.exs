defmodule ShotElixirWeb.Api.V2.BacklinkControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{Factory, Accounts}

  describe "index" do
    setup %{conn: conn} do
      conn = put_req_header(conn, "accept", "application/json")
      %{conn: conn}
    end

    test "returns backlinks scoped to campaign and limited", %{conn: conn} do
      campaign = Factory.insert(:campaign)
      target = Factory.insert(:character, %{campaign: campaign})

      # Two entities in campaign referencing target
      Factory.insert(:character, %{campaign: campaign, mentions: %{"character" => [target.id]}})
      Factory.insert(:site, %{campaign: campaign, mentions: %{"character" => [target.id]}})

      # An entity in another campaign should not appear
      other_campaign = Factory.insert(:campaign)

      Factory.insert(:character, %{
        campaign: other_campaign,
        mentions: %{"character" => [target.id]}
      })

      {:ok, user} =
        campaign.user_id
        |> Accounts.get_user!()
        |> Accounts.set_current_campaign(campaign.id)

      conn = authenticate(conn, user)

      conn = get(conn, ~p"/api/v2/backlinks/character/#{target.id}")

      assert %{"backlinks" => backlinks} = json_response(conn, 200)
      assert length(backlinks) == 2
      assert Enum.any?(backlinks, &(&1["entity_class"] == "Character"))
      assert Enum.any?(backlinks, &(&1["entity_class"] == "Site"))
    end

    test "returns 422 when no campaign set", %{conn: conn} do
      user = Factory.insert(:user)
      target = Factory.insert(:character)

      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/backlinks/character/#{target.id}")

      assert %{"error" => "No active campaign selected"} = json_response(conn, 422)
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _claims} = ShotElixir.Guardian.encode_and_sign(user, %{})
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
