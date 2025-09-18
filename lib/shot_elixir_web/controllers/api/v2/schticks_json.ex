defmodule ShotElixirWeb.Api.V2.SchticksJSON do
  alias ShotElixir.Schticks.Schtick

  def index(%{schticks: schticks}) do
    %{schticks: Enum.map(schticks, &schtick_json/1)}
  end

  def show(%{schtick: schtick}) do
    %{schtick: schtick_json(schtick)}
  end

  def error(%{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  defp schtick_json(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      description: schtick.description,
      category: schtick.category,
      path: schtick.path,
      color: schtick.color,
      image_url: schtick.image_url,
      bonus: schtick.bonus,
      archetypes: schtick.archetypes,
      active: schtick.active,
      campaign_id: schtick.campaign_id,
      prerequisite_id: schtick.prerequisite_id,
      prerequisite:
        if schtick.prerequisite do
          %{
            id: schtick.prerequisite.id,
            name: schtick.prerequisite.name,
            category: schtick.prerequisite.category
          }
        else
          nil
        end,
      created_at: schtick.created_at,
      updated_at: schtick.updated_at
    }
  end
end
