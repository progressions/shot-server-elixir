defmodule ShotElixirWeb.Api.V2.LocationConnectionView do
  def render("index.json", %{connections: connections}) do
    %{
      location_connections: Enum.map(connections, &render_connection/1),
      meta: %{
        total_count: length(connections)
      }
    }
  end

  def render("show.json", %{connection: connection}) do
    render_connection(connection)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      errors: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
    }
  end

  defp render_connection(connection) do
    %{
      id: connection.id,
      from_location_id: connection.from_location_id,
      to_location_id: connection.to_location_id,
      bidirectional: connection.bidirectional,
      label: connection.label,
      from_location: render_location(connection.from_location),
      to_location: render_location(connection.to_location),
      created_at: connection.created_at,
      updated_at: connection.updated_at
    }
  end

  defp render_location(nil), do: nil

  defp render_location(location) do
    %{
      id: location.id,
      name: location.name,
      color: location.color
    }
  end

  defp translate_error({msg, opts}) do
    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end
end
