defmodule ShotElixirWeb.Api.V2.JunctureController do
  use ShotElixirWeb, :controller
  
  def index(conn, _params), do: json(conn, %{junctures: []})
  def show(conn, _params), do: json(conn, %{juncture: %{}})
  def create(conn, _params), do: json(conn, %{juncture: %{}})
  def update(conn, _params), do: json(conn, %{juncture: %{}})
  def delete(conn, _params), do: send_resp(conn, :no_content, "")
end
