defmodule ShotElixirWeb.DashboardTest do
  use ShotElixirWeb.ConnCase, async: true

  test "GET /dev/dashboard", %{conn: conn} do
    conn = get(conn, ~p"/dev/dashboard")
    assert conn.status == 302
    assert redirected_to(conn) == "/dev/dashboard/home"

    conn = get(conn, "/dev/dashboard/home")
    assert html_response(conn, 200) =~ "Dashboard"
  end

  # Oban.Web requires a fully running Oban instance which is disabled in tests
  @tag :skip
  test "GET /dev/oban", %{conn: conn} do
    conn = get(conn, ~p"/dev/oban")
    assert html_response(conn, 200) =~ "Oban"
  end
end
