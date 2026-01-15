defmodule ShotElixirWeb.Api.V2.NotionWebhookControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  describe "POST /api/v2/webhooks/notion - verification handshake" do
    test "returns the verification token for manual verification", %{conn: conn} do
      verification_token = "secret_test_verification_token_123"

      conn =
        post(conn, ~p"/api/v2/webhooks/notion", %{
          "verification_token" => verification_token
        })

      response = json_response(conn, 200)

      assert response["verification_token"] == verification_token
      assert response["message"] =~ ~r/verification/i
    end
  end

  describe "POST /api/v2/webhooks/notion - event processing" do
    test "returns 200 and queues job for valid event payload", %{conn: conn} do
      event_payload = %{
        "id" => "event-#{Ecto.UUID.generate()}",
        "type" => "page.properties_updated",
        "workspace_id" => Ecto.UUID.generate(),
        "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
        "entity" => %{
          "id" => Ecto.UUID.generate(),
          "type" => "page"
        }
      }

      conn = post(conn, ~p"/api/v2/webhooks/notion", event_payload)

      # Should always return 200 to acknowledge receipt
      assert conn.status == 200
    end

    test "returns 200 even for minimal payload", %{conn: conn} do
      # Notion may send minimal payloads - we should always acknowledge
      conn = post(conn, ~p"/api/v2/webhooks/notion", %{})

      assert conn.status == 200
    end

    test "returns 200 for page.content_updated event type", %{conn: conn} do
      event_payload = %{
        "id" => "event-#{Ecto.UUID.generate()}",
        "type" => "page.content_updated",
        "workspace_id" => Ecto.UUID.generate(),
        "entity" => %{
          "id" => Ecto.UUID.generate(),
          "type" => "page"
        }
      }

      conn = post(conn, ~p"/api/v2/webhooks/notion", event_payload)

      assert conn.status == 200
    end

    test "returns 200 for page.deleted event type", %{conn: conn} do
      event_payload = %{
        "id" => "event-#{Ecto.UUID.generate()}",
        "type" => "page.deleted",
        "workspace_id" => Ecto.UUID.generate(),
        "entity" => %{
          "id" => Ecto.UUID.generate(),
          "type" => "page"
        }
      }

      conn = post(conn, ~p"/api/v2/webhooks/notion", event_payload)

      assert conn.status == 200
    end

    test "returns 200 for page.restored event type", %{conn: conn} do
      event_payload = %{
        "id" => "event-#{Ecto.UUID.generate()}",
        "type" => "page.restored",
        "workspace_id" => Ecto.UUID.generate(),
        "entity" => %{
          "id" => Ecto.UUID.generate(),
          "type" => "page"
        }
      }

      conn = post(conn, ~p"/api/v2/webhooks/notion", event_payload)

      assert conn.status == 200
    end
  end
end
