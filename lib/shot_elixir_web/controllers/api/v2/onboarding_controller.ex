defmodule ShotElixirWeb.Api.V2.OnboardingController do
  use ShotElixirWeb, :controller

  def dismiss_congratulations(conn, _params), do: json(conn, %{success: true})
  def update(conn, _params), do: json(conn, %{success: true})
end
