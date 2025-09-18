defmodule ShotElixirWeb.Api.V2.FactionController do
  use ShotElixirWeb, :controller
  
  def index(conn, _params), do: json(conn, %{factions: []})
  def show(conn, _params), do: json(conn, %{faction: %{}})
  def create(conn, _params), do: json(conn, %{faction: %{}})
  def update(conn, _params), do: json(conn, %{faction: %{}})
  def delete(conn, _params), do: send_resp(conn, :no_content, "")
end
