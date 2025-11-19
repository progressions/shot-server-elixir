defmodule ShotElixirWeb.Api.V2.VehicleView do
  alias ShotElixir.JsonSanitizer

  def render("index.json", %{vehicles: vehicles, meta: meta}) do
    %{
      vehicles: Enum.map(vehicles, &render_vehicle/1),
      meta: meta
    }
    |> JsonSanitizer.sanitize()
  end

  def render("show.json", %{vehicle: vehicle}) do
    render_vehicle_detail(vehicle)
    |> JsonSanitizer.sanitize()
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
      image_url: get_image_url(vehicle),
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
