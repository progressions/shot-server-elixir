defmodule ShotElixirWeb.Api.V2.SiteController do
  use ShotElixirWeb, :controller
  
  def index(conn, _params), do: json(conn, %{sites: []})
  def show(conn, _params), do: json(conn, %{site: %{}})
  def create(conn, _params), do: json(conn, %{site: %{}})
  def update(conn, _params), do: json(conn, %{site: %{}})
  def delete(conn, _params), do: send_resp(conn, :no_content, "")
end
