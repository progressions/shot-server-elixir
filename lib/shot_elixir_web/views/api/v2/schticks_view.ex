defmodule ShotElixirWeb.Api.V2.SchticksView do
  def render("index.json", %{schticks: schticks, meta: meta}) do
    %{
      schticks: Enum.map(schticks, &render_schtick/1),
      meta: meta
    }
  end

  def render("batch.json", %{data: data}) do
    %{
      schticks: Enum.map(data.schticks, &render_encounter_schtick/1),
      categories: data.categories,
      meta: data.meta
    }
  end

  def render("show.json", %{schtick: schtick}) do
    render_schtick_detail(schtick)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  defp render_schtick(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      description: schtick.description,
      image_url: get_image_url(schtick),
      category: schtick.category,
      path: schtick.path,
      prerequisite_id: schtick.prerequisite_id,
      active: schtick.active,
      created_at: schtick.created_at,
      updated_at: schtick.updated_at,
      entity_class: "Schtick"
    }
  end


  defp render_encounter_schtick(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      description: schtick.description,
      category: schtick.category,
      path: schtick.path,
      entity_class: "Schtick"
    }
  end

  defp render_schtick_detail(schtick) do
    base = render_schtick(schtick)

    # Add associations if they're loaded
    prerequisite =
      case Map.get(schtick, :prerequisite) do
        %Ecto.Association.NotLoaded{} -> nil
        prerequisite -> render_prerequisite(prerequisite)
      end

    Map.merge(base, %{
      prerequisite: prerequisite
    })
  end

  defp render_prerequisite(nil), do: nil

  defp render_prerequisite(prerequisite) do
    %{
      id: prerequisite.id,
      name: prerequisite.name,
      category: prerequisite.category
    }
  end

  # Rails-compatible image URL handling
  defp get_image_url(record) when is_map(record) do
    # Check if image_url is already in the record (pre-loaded)
    case Map.get(record, :image_url) do
      nil ->
        # Try to get entity type from struct, fallback to nil if plain map
        entity_type =
          case Map.get(record, :__struct__) do
            # Plain map, skip ActiveStorage lookup
            nil -> nil
            struct_module -> struct_module |> Module.split() |> List.last()
          end

        if entity_type && Map.get(record, :id) do
          ShotElixir.ActiveStorage.get_image_url(entity_type, record.id)
        else
          nil
        end

      url ->
        url
    end
  end

  defp get_image_url(_), do: nil
end
