defmodule ShotElixirWeb.Api.V2.SearchView do
  use ShotElixirWeb, :view

  def render("index.json", %{results: results}) do
    %{results: results}
  end
end
