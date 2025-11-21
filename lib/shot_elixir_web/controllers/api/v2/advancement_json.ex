defmodule ShotElixirWeb.Api.V2.AdvancementJSON do
  @moduledoc """
  JSON module for rendering Advancement JSON responses.
  Matches Rails AdvancementSerializer format for API compatibility.
  """

  def render("index.json", %{advancements: advancements}) do
    Enum.map(advancements, &render_advancement/1)
  end

  def render("show.json", %{advancement: advancement}) do
    render_advancement(advancement)
  end

  defp render_advancement(advancement) do
    %{
      id: advancement.id,
      description: advancement.description,
      character_id: advancement.character_id,
      created_at: advancement.created_at,
      updated_at: advancement.updated_at
    }
  end
end
