defmodule ShotElixirWeb.Api.V2.WeaponController do
  use ShotElixirWeb, :controller
  
  def index(conn, _params), do: json(conn, %{weapons: []})
  def show(conn, _params), do: json(conn, %{weapon: %{}})
  def create(conn, _params), do: json(conn, %{weapon: %{}})
  def update(conn, _params), do: json(conn, %{weapon: %{}})
  def delete(conn, _params), do: send_resp(conn, :no_content, "")
end
