defmodule ShotElixirWeb.Api.V2.PartyController do
  use ShotElixirWeb, :controller
  
  def index(conn, _params), do: json(conn, %{parties: []})
  def show(conn, _params), do: json(conn, %{party: %{}})
  def create(conn, _params), do: json(conn, %{party: %{}})
  def update(conn, _params), do: json(conn, %{party: %{}})
  def delete(conn, _params), do: send_resp(conn, :no_content, "")
end
