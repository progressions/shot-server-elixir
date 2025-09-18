defmodule ShotElixirWeb.Api.V2.EncounterController do
  use ShotElixirWeb, :controller
  
  def show(conn, _params), do: json(conn, %{encounter: %{}})
  def act(conn, _params), do: json(conn, %{success: true})
  def apply_combat_action(conn, _params), do: json(conn, %{success: true})
  def apply_chase_action(conn, _params), do: json(conn, %{success: true})
  def update_initiatives(conn, _params), do: json(conn, %{success: true})
end
