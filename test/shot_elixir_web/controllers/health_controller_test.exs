defmodule ShotElixirWeb.HealthControllerTest do
  use ShotElixirWeb.ConnCase

  describe "GET /health" do
    test "returns ok status", %{conn: conn} do
      conn = get(conn, "/health")

      assert json_response(conn, 200) == %{
        "status" => "ok",
        "service" => "shot_elixir"
      }
    end
  end
end