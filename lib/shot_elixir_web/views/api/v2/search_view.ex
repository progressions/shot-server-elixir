defmodule ShotElixirWeb.Api.V2.SearchView do
  def render("index.json", %{results: results}) do
    %{results: results}
  end
end
