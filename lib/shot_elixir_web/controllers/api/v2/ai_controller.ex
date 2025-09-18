defmodule ShotElixirWeb.Api.V2.AiController do
  use ShotElixirWeb, :controller
  
  def create(conn, _params), do: json(conn, %{ai_result: %{}})
  def extend(conn, _params), do: json(conn, %{ai_result: %{}})
end
