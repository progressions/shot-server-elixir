defmodule ShotElixirWeb.CableController do
  use ShotElixirWeb, :controller

  require Logger

  @doc """
  Responds to plain HTTP requests made to the ActionCable-compatible endpoint.
  This is primarily used by health checks and probing tools; real WebSocket
  upgrades bypass this controller entirely.
  """
  def show(conn, _params) do
    Logger.debug("[CableController] headers=#{inspect(conn.req_headers)}")

    conn
    |> put_resp_header("x-actioncable", "available")
    |> json(%{status: "ok", message: "WebSocket endpoint ready"})
  end
end
