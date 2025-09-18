defmodule ShotElixirWeb.Api.V2.InvitationController do
  use ShotElixirWeb, :controller
  
  def index(conn, _params), do: json(conn, %{invitations: []})
  def show(conn, _params), do: json(conn, %{invitation: %{}})
  def create(conn, _params), do: json(conn, %{invitation: %{}})
  def update(conn, _params), do: json(conn, %{invitation: %{}})
  def delete(conn, _params), do: send_resp(conn, :no_content, "")
end
