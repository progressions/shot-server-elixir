defmodule ShotElixirWeb.Api.V2.SchticksView do
  def render("index.json", %{data: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{
        schticks: schticks,
        categories: categories,
        paths: paths,
        meta: meta,
        is_autocomplete: is_autocomplete
      } ->
        schtick_serializer =
          if is_autocomplete, do: &render_schtick_autocomplete/1, else: &render_schtick/1

        %{
          schticks: Enum.map(schticks, schtick_serializer),
          categories: categories,
          paths: paths,
          meta: meta
        }

      %{schticks: schticks, categories: categories, paths: paths, meta: meta} ->
        %{
          schticks: Enum.map(schticks, &render_schtick/1),
          categories: categories,
          paths: paths,
          meta: meta
        }

      schticks when is_list(schticks) ->
        # Legacy format for backward compatibility
        %{
          schticks: Enum.map(schticks, &render_schtick/1),
          categories: [],
          paths: [],
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(schticks),
            total_pages: 1
          }
        }
    end
  end

  def render("batch.json", %{data: data}) do
    %{
      schticks: Enum.map(data.schticks, &render_encounter_schtick/1),
      categories: data.categories,
      meta: data.meta
    }
  end

  def render("show.json", %{schtick: schtick}) do
    %{schtick: render_schtick_detail(schtick)}
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
      category: schtick.category,
      path: schtick.path,
      prerequisite_id: schtick.prerequisite_id,
      active: schtick.active,
      created_at: schtick.created_at,
      updated_at: schtick.updated_at
    }
  end

  defp render_schtick_autocomplete(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      category: schtick.category,
      active: schtick.active
    }
  end

  defp render_encounter_schtick(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      description: schtick.description,
      category: schtick.category,
      path: schtick.path
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
end
