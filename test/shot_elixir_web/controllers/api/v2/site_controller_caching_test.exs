defmodule ShotElixirWeb.Api.V2.SiteControllerCachingTest do
  @moduledoc """
  Tests for HTTP caching behavior in the Site controller.

  Tests ETag-based conditional requests and Cache-Control headers.
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.{Sites, Campaigns, Accounts}
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    {:ok, gamemaster} =
      Accounts.create_user(%{
        email: "site_caching_gm@example.com",
        password: "password123",
        first_name: "Site",
        last_name: "Master",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Site Caching Test Campaign",
        description: "Campaign for site caching tests",
        user_id: gamemaster.id
      })

    {:ok, gm_with_campaign} = Accounts.set_current_campaign(gamemaster, campaign.id)

    {:ok, site} =
      Sites.create_site(%{
        name: "Cacheable Site",
        campaign_id: campaign.id
      })

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     gamemaster: gm_with_campaign,
     campaign: campaign,
     site: site}
  end

  describe "show caching" do
    test "returns ETag header on successful response", %{
      conn: conn,
      gamemaster: gm,
      site: site
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/sites/#{site.id}")

      assert conn.status == 200
      [etag] = get_resp_header(conn, "etag")
      assert etag =~ ~r/^"[a-f0-9]{32}"$/
    end

    test "returns Cache-Control header on successful response", %{
      conn: conn,
      gamemaster: gm,
      site: site
    } do
      conn = authenticate(conn, gm)
      conn = get(conn, ~p"/api/v2/sites/#{site.id}")

      assert conn.status == 200
      [cache_control] = get_resp_header(conn, "cache-control")
      assert cache_control == "private, no-cache, must-revalidate"
    end

    test "returns 304 Not Modified when If-None-Match matches ETag", %{
      conn: conn,
      gamemaster: gm,
      site: site
    } do
      # First request to get the ETag
      conn1 = authenticate(conn, gm)
      conn1 = get(conn1, ~p"/api/v2/sites/#{site.id}")
      [etag] = get_resp_header(conn1, "etag")

      # Second request with If-None-Match header
      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> authenticate(gm)
        |> put_req_header("if-none-match", etag)
        |> get(~p"/api/v2/sites/#{site.id}")

      assert conn2.status == 304
      assert conn2.resp_body == ""
      # Still returns ETag on 304
      assert get_resp_header(conn2, "etag") == [etag]
      # Still returns Cache-Control on 304
      [cache_control] = get_resp_header(conn2, "cache-control")
      assert cache_control == "private, no-cache, must-revalidate"
    end

    test "returns 200 when If-None-Match does not match current ETag", %{
      conn: conn,
      gamemaster: gm,
      site: site
    } do
      conn =
        conn
        |> authenticate(gm)
        |> put_req_header("if-none-match", "\"stale-etag-12345\"")
        |> get(~p"/api/v2/sites/#{site.id}")

      assert conn.status == 200
      response = json_response(conn, 200)
      assert response["id"] == site.id
    end

    test "returns new ETag after site is updated", %{
      conn: conn,
      gamemaster: gm,
      site: site
    } do
      # Get initial ETag
      conn1 = authenticate(conn, gm)
      conn1 = get(conn1, ~p"/api/v2/sites/#{site.id}")
      [etag1] = get_resp_header(conn1, "etag")

      # Update the site - wait a moment to ensure updated_at changes
      # (database timestamps may have second precision)
      Process.sleep(1100)
      {:ok, _updated} = Sites.update_site(site, %{name: "Updated Site Name"})

      # Get new ETag - should be different
      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> authenticate(gm)
        |> get(~p"/api/v2/sites/#{site.id}")

      [etag2] = get_resp_header(conn2, "etag")
      assert etag1 != etag2
    end

    test "304 response preserves bandwidth by not sending body", %{
      conn: conn,
      gamemaster: gm,
      site: site
    } do
      # First request to get ETag
      conn1 = authenticate(conn, gm)
      conn1 = get(conn1, ~p"/api/v2/sites/#{site.id}")
      [etag] = get_resp_header(conn1, "etag")
      body_size = byte_size(conn1.resp_body)
      assert body_size > 0

      # Second request should have empty body
      conn2 =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> authenticate(gm)
        |> put_req_header("if-none-match", etag)
        |> get(~p"/api/v2/sites/#{site.id}")

      assert byte_size(conn2.resp_body) == 0
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
