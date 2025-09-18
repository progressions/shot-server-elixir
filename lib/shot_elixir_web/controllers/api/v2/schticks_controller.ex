defmodule ShotElixirWeb.Api.V2.SchticksController do
  use ShotElixirWeb, :controller
  
  def index(conn, _params), do: json(conn, %{schticks: []})
  def show(conn, _params), do: json(conn, %{schtick: %{}})
  def create(conn, _params), do: json(conn, %{schtick: %{}})
  def update(conn, _params), do: json(conn, %{schtick: %{}})
  def delete(conn, _params), do: send_resp(conn, :no_content, "")
end
