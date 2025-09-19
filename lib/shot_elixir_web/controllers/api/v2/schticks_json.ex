defmodule ShotElixirWeb.Api.V2.SchticksJSON do
  alias ShotElixir.Schticks.Schtick

  def index(%{schticks: data}) when is_map(data) do
    # Handle paginated response with metadata
    %{
      schticks: Enum.map(data.schticks, &schtick_json/1),
      paths: data[:paths] || [],
      categories: data[:categories] || [],
      meta: data[:meta] || %{},
      is_autocomplete: data[:is_autocomplete] || false
    }
  end

  def index(%{schticks: schticks}) when is_list(schticks) do
    # Handle simple list response
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

  defp schtick_json(schtick) when is_map(schtick) do
    prerequisite =
      case Map.get(schtick, :prerequisite) do
        %Ecto.Association.NotLoaded{} -> nil
        nil -> nil
        prerequisite when is_map(prerequisite) -> %{
          id: Map.get(prerequisite, :id),
          name: Map.get(prerequisite, :name),
          category: Map.get(prerequisite, :category)
        }
        _ -> nil
      end

    %{
      id: Map.get(schtick, :id),
      name: Map.get(schtick, :name),
      description: Map.get(schtick, :description),
      category: Map.get(schtick, :category),
      path: Map.get(schtick, :path),
      color: Map.get(schtick, :color),
      image_url: Map.get(schtick, :image_url),
      bonus: Map.get(schtick, :bonus),
      archetypes: Map.get(schtick, :archetypes),
      active: Map.get(schtick, :active, true),
      campaign_id: Map.get(schtick, :campaign_id),
      prerequisite_id: Map.get(schtick, :prerequisite_id),
      prerequisite: prerequisite,
      created_at: Map.get(schtick, :created_at),
      updated_at: Map.get(schtick, :updated_at)
    }
  end
end
