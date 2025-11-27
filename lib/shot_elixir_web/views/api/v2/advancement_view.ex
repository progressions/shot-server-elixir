defmodule ShotElixirWeb.Api.V2.AdvancementView do
  def render("index.json", %{advancements: advancements}) do
    Enum.map(advancements, &render_advancement/1)
  end

  def render("show.json", %{advancement: advancement}) do
    render_advancement(advancement)
  end

  def render("error.json", %{changeset: changeset}) do
    %{errors: translate_errors(changeset)}
  end

  def render("error.json", %{error: error}) do
    %{error: error}
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

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
