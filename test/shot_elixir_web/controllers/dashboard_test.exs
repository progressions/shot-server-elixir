defmodule ShotElixirWeb.DashboardTest do
  use ShotElixirWeb.ConnCase, async: true

  # Setup basic auth headers
  setup %{conn: conn} do
    auth = Plug.BasicAuth.encode_basic_auth("admin", "admin")
    conn = put_req_header(conn, "authorization", auth)
    {:ok, conn: conn}
  end

  test "GET /admin/dashboard", %{conn: conn} do
    conn = get(conn, "/admin/dashboard")
    assert conn.status == 302
    assert redirected_to(conn) == "/admin/dashboard/home"

    conn = get(conn, "/admin/dashboard/home")
    assert html_response(conn, 200) =~ "Dashboard"
  end

  test "GET /admin/dashboard without auth", %{conn: conn} do
    # Create a fresh conn without auth headers
    conn = build_conn()
    conn = get(conn, "/admin/dashboard")
    assert conn.status == 401
  end

  # Oban.Web requires a fully running Oban instance which is disabled in tests
  @tag :skip
  test "GET /admin/oban", %{conn: conn} do
    conn = get(conn, "/admin/oban")
    assert html_response(conn, 200) =~ "Oban"
  end
end
