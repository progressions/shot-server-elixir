defmodule ShotElixirWeb.Api.V2.VehicleControllerCachingTest do
  @moduledoc """
  Tests for HTTP caching behavior in the Vehicle controller.

  Tests ETag-based conditional requests and Cache-Control headers.
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{Vehicles, Campaigns, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "vehicle_caching_gm@example.com",
        password: "password123",
        first_name: "Vehicle",
        last_name: "Master",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Vehicle Caching Test Campaign",
        description: "Campaign for vehicle caching tests",
        user_id: gamemaster.id
      })

    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)

    {:ok, vehicle} =
      Vehicles.create_vehicle(%{
        name: "Cacheable Vehicle",
        campaign_id: campaign.id,
        user_id: gamemaster.id
      })

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gm_with_campaign,
     campaign: campaign,
     vehicle: vehicle}
  end

  describe "show caching" do
    test "returns ETag header on successful response", %{
      conn: conn,
      gamemaster: gm,
      vehicle: vehicle
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/vehicles/#{vehicle.id}")

      assert conn.status == 200
      [etag] = get_resp_header(conn, "etag")
      assert etag =~ ~r/^"[a-f0-9]{32}"$/
    end

    test "returns Cache-Control header on successful response", %{
      conn: conn,
      gamemaster: gm,
      vehicle: vehicle
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/vehicles/#{vehicle.id}")

      assert conn.status == 200
      [cache_control] = get_resp_header(conn, "cache-control")
      assert cache_control == "private, max-age=60, must-revalidate"
    end

    test "returns 304 Not Modified when If-None-Match matches ETag", %{
      conn: conn,
      gamemaster: gm,
      vehicle: vehicle
    } do
      # First request to get the ETag
      conn1 = authenticate(conn, gm)
      conn1 = get(conn1, ~p"/api/v2/vehicles/#{vehicle.id}")
      [etag] = get_resp_header(conn1, "etag")

      # Second request with If-None-Match header
      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> authenticate(gm)
        |> put_req_header("if-none-match", etag)
        |> get(~p"/api/v2/vehicles/#{vehicle.id}")

      assert conn2.status == 304
      assert conn2.resp_body == ""
      # Still returns ETag on 304
      assert get_resp_header(conn2, "etag") == [etag]
      # Still returns Cache-Control on 304
      [cache_control] = get_resp_header(conn2, "cache-control")
      assert cache_control == "private, max-age=60, must-revalidate"
    end

    test "returns 200 when If-None-Match does not match current ETag", %{
      conn: conn,
      gamemaster: gm,
      vehicle: vehicle
    } do
      conn =
        conn
        |> authenticate(gm)
        |> put_req_header("if-none-match", "\"stale-etag-12345\"")
        |> get(~p"/api/v2/vehicles/#{vehicle.id}")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["id"] == vehicle.id
    end

    test "returns new ETag after vehicle is updated", %{
      conn: conn,
      gamemaster: gm,
      vehicle: vehicle
    } do
      # Get initial ETag
      conn1 = authenticate(conn, gm)
      conn1 = get(conn1, ~p"/api/v2/vehicles/#{vehicle.id}")
      [etag1] = get_resp_header(conn1, "etag")

      # Update the vehicle - wait a moment to ensure updated_at changes
      # (database timestamps may have second precision)
      Process.sleep(1100)
      {:ok, _updated} = Vehicles.update_vehicle(vehicle, %{name: "Updated Vehicle Name"})

      # Get new ETag - should be different
      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> authenticate(gm)
        |> get(~p"/api/v2/vehicles/#{vehicle.id}")

      [etag2] = get_resp_header(conn2, "etag")
      assert etag1 != etag2
    end

    test "304 response preserves bandwidth by not sending body", %{
      conn: conn,
      gamemaster: gm,
      vehicle: vehicle
    } do
      # First request to get ETag
      conn1 = authenticate(conn, gm)
      conn1 = get(conn1, ~p"/api/v2/vehicles/#{vehicle.id}")
      [etag] = get_resp_header(conn1, "etag")
      body_size = byte_size(conn1.resp_body)
      assert body_size > 0

      # Second request should have empty body
      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> authenticate(gm)
        |> put_req_header("if-none-match", etag)
        |> get(~p"/api/v2/vehicles/#{vehicle.id}")

      assert byte_size(conn2.resp_body) == 0
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
