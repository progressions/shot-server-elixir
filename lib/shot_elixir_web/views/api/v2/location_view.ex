defmodule ShotElixirWeb.Api.V2.LocationView do
  def render("index.json", %{locations: locations}) do
    %{
      locations: Enum.map(locations, &render_location/1)
    }
  end

  def render("show.json", %{location: location}) do
    render_location(location)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  @doc """
  Render a location for index listings.
  """
  def render_for_index(location), do: render_location(location)

  defp render_location(location) do
    %{
      id: location.id,
      name: location.name,
      description: location.description,
      color: location.color,
      image_url: location.image_url,
      fight_id: location.fight_id,
      site_id: location.site_id,
      copied_from_location_id: location.copied_from_location_id,
      shots: render_shots_if_loaded(location),
      connections: render_connections(location),
      created_at: location.created_at,
      updated_at: location.updated_at,
      entity_class: "Location"
    }
  end

  defp render_shots_if_loaded(location) do
    case Map.get(location, :shots) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      shots -> Enum.map(shots, &render_shot_lite/1)
    end
  end

  defp render_shot_lite(shot) do
    %{
      id: shot.id,
      shot: shot.shot,
      character_id: shot.character_id,
      vehicle_id: shot.vehicle_id
    }
  end

  defp render_connections(location) do
    from_connections = render_connections_if_loaded(location, :from_connections)
    to_connections = render_connections_if_loaded(location, :to_connections)

    # Combine and deduplicate for bidirectional connections
    from_connections ++ to_connections
  end

  defp render_connections_if_loaded(location, key) do
    case Map.get(location, key) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      connections -> Enum.map(connections, &render_connection/1)
    end
  end

  defp render_connection(connection) do
    %{
      id: connection.id,
      from_location_id: connection.from_location_id,
      to_location_id: connection.to_location_id,
      bidirectional: connection.bidirectional,
      label: connection.label
    }
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
