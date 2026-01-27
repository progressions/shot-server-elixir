defmodule ShotElixirWeb.Api.V2.EffectView do
  @moduledoc """
  View for rendering fight-level effects.
  """

  def render("index.json", %{effects: effects}) do
    %{
      effects: Enum.map(effects, &render_effect/1)
    }
  end

  def render("show.json", %{effect: effect}) do
    render_effect(effect)
  end

  def render("effect.json", %{effect: effect}) do
    render_effect(effect)
  end

  def render("error.json", %{changeset: changeset}) do
    %{errors: translate_errors(changeset)}
  end

  def render("error.json", %{error: error}) do
    %{error: error}
  end

  defp render_effect(effect) do
    %{
      id: effect.id,
      name: effect.name,
      description: effect.description,
      severity: effect.severity,
      start_sequence: effect.start_sequence,
      end_sequence: effect.end_sequence,
      start_shot: effect.start_shot,
      end_shot: effect.end_shot,
      fight_id: effect.fight_id,
      user_id: effect.user_id,
      created_at: effect.created_at
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
