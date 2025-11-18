defmodule ShotElixirWeb.Api.V2.EncounterView do
  def render("show.json", %{encounter: encounter}) do
    render_encounter(encounter)
  end

  def render("error.json", %{errors: errors}) do
    %{
      success: false,
      errors: translate_errors(errors)
    }
  end

  def render("error.json", %{error: error}) do
    %{
      success: false,
      errors: %{base: [error]}
    }
  end

  defp render_encounter(fight) do
    %{
      id: fight.id,
      entity_class: "Fight",
      name: fight.name,
      sequence: fight.sequence,
      description: fight.description,
      started_at: fight.started_at,
      ended_at: fight.ended_at,
      image_url: get_image_url(fight),
      character_ids: get_character_ids(fight),
      vehicle_ids: get_vehicle_ids(fight),
      action_id: fight.action_id,
      shots: render_shots(fight)
    }
  end

  defp render_shots(fight) do
    # TODO: Implement complex shot serialization like Rails EncounterSerializer
    # For now, return empty array to prevent frontend errors
    []
  end

  defp get_character_ids(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      shots ->
        shots
        |> Enum.filter(& &1.character_id)
        |> Enum.map(& &1.character_id)
        |> Enum.uniq()
    end
  end

  defp get_vehicle_ids(fight) do
    case Map.get(fight, :shots) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      shots ->
        shots
        |> Enum.filter(& &1.vehicle_id)
        |> Enum.map(& &1.vehicle_id)
        |> Enum.uniq()
    end
  end

  defp get_image_url(fight) do
    # TODO: Implement proper image attachment checking
    Map.get(fight, :image_url)
  end

  defp translate_errors(changeset) when is_map(changeset) do
    if Map.has_key?(changeset, :errors) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    else
      changeset
    end
  end

  defp translate_errors(errors), do: errors
end