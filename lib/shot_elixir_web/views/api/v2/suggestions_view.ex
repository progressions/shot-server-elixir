defmodule ShotElixirWeb.Api.V2.SuggestionsView do
  @moduledoc """
  View module for rendering suggestions responses.
  """

  def render("index.json", %{suggestions: suggestions}) do
    suggestions
  end
end
