defmodule ShotElixirWeb.Api.V2.VehicleView do
  def render("index.json", %{vehicles: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{
        vehicles: vehicles,
        factions: factions,
        archetypes: archetypes,
        types: types,
        meta: meta,
        is_autocomplete: is_autocomplete
      } ->
        vehicle_serializer =
          if is_autocomplete, do: &render_vehicle_autocomplete/1, else: &render_vehicle/1

        %{
          vehicles: Enum.map(vehicles, vehicle_serializer),
          factions: factions,
          archetypes: archetypes,
          types: types,
          meta: meta
        }

      %{vehicles: vehicles, factions: factions, archetypes: archetypes, types: types, meta: meta} ->
        %{
          vehicles: Enum.map(vehicles, &render_vehicle/1),
          factions: factions,
          archetypes: archetypes,
          types: types,
          meta: meta
        }

      vehicles when is_list(vehicles) ->
        # Legacy format for backward compatibility
        %{
          vehicles: Enum.map(vehicles, &render_vehicle/1),
          factions: [],
          archetypes: [],
          types: [],
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(vehicles),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{vehicle: vehicle}) do
    %{
      vehicle: render_vehicle_detail(vehicle)
    }
  end

  def render("archetypes.json", %{archetypes: archetypes}) do
    archetypes
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

  defp render_vehicle(vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      description: vehicle.description,
      color: vehicle.color,
      impairments: vehicle.impairments,
      campaign_id: vehicle.campaign_id,
      user_id: vehicle.user_id,
      faction_id: vehicle.faction_id,
      juncture_id: vehicle.juncture_id,
      action_values: vehicle.action_values,
      active: vehicle.active,
      created_at: vehicle.created_at,
      updated_at: vehicle.updated_at,
      entity_class: "Vehicle"
    }
  end

  defp render_vehicle_autocomplete(vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name,
      active: vehicle.active,
      entity_class: "Vehicle"
    }
  end

  defp render_vehicle_detail(vehicle) do
    base = render_vehicle(vehicle)

    # Add associations if they're loaded
    user =
      case Map.get(vehicle, :user) do
        %Ecto.Association.NotLoaded{} -> nil
        user -> render_user(user)
      end

    faction =
      case Map.get(vehicle, :faction) do
        %Ecto.Association.NotLoaded{} -> nil
        faction -> render_faction(faction)
      end

    Map.merge(base, %{
      user: user,
      faction: faction
    })
  end

  defp render_user(nil), do: nil

  defp render_user(user) do
    %{
      id: user.id,
      name: user.name,
      email: user.email
    }
  end

  defp render_faction(nil), do: nil

  defp render_faction(faction) do
    %{
      id: faction.id,
      name: faction.name
    }
  end
end
