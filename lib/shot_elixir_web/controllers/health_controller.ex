defmodule ShotElixirWeb.HealthController do
  use ShotElixirWeb, :controller

  def show(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok", service: "shot_elixir"})
  end
end
