defmodule ShotElixirWeb.Api.V2.CharacterEffectView do
  def render("index.json", %{character_effects: character_effects}) do
    %{
      character_effects: Enum.map(character_effects, &render_character_effect/1)
    }
  end

  def render("show.json", %{character_effect: character_effect}) do
    render_character_effect(character_effect)
  end

  def render("error.json", %{changeset: changeset}) do
    %{errors: translate_errors(changeset)}
  end

  def render("error.json", %{error: error}) do
    %{error: error}
  end

  defp render_character_effect(character_effect) do
    %{
      id: character_effect.id,
      name: character_effect.name,
      description: character_effect.description,
      severity: character_effect.severity,
      action_value: character_effect.action_value,
      change: character_effect.change,
      character_id: character_effect.character_id,
      vehicle_id: character_effect.vehicle_id,
      shot_id: character_effect.shot_id,
      end_sequence: character_effect.end_sequence,
      end_shot: character_effect.end_shot,
      created_at: character_effect.created_at,
      updated_at: character_effect.updated_at
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
