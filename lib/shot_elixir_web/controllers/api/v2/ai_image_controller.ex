defmodule ShotElixirWeb.Api.V2.AiImageController do
  use ShotElixirWeb, :controller
  
  def create(conn, _params), do: json(conn, %{ai_image: %{}})
  def attach(conn, _params), do: json(conn, %{success: true})
end
