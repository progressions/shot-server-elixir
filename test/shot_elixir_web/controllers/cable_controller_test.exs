defmodule ShotElixirWeb.CableControllerTest do
  use ShotElixirWeb.ConnCase, async: true

  test "GET /cable returns readiness payload", %{conn: conn} do
    conn = get(conn, "/cable")

    assert json_response(conn, 200) == %{
             "status" => "ok",
             "message" => "WebSocket endpoint ready"
           }

    assert get_resp_header(conn, "x-actioncable") == ["available"]
  end
end
