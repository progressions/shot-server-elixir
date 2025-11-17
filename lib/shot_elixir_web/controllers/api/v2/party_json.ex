defmodule ShotElixirWeb.Api.V2.PartyJSON do
  require Logger

  def index(%{parties: data}) when is_map(data) do
    # Handle paginated response with metadata
    %{
      parties: Enum.map(data.parties, &party_json/1),
      factions: data[:factions] || [],
      meta: data[:meta] || %{}
    }
  end

  def index(%{parties: parties}) when is_list(parties) do
    # Handle simple list response
    %{parties: Enum.map(parties, &party_json/1)}
  end

  def show(%{party: party}) do
    party_json_with_members(party)
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

  defp party_json(party) when is_map(party) do
    %{
      id: Map.get(party, :id),
      name: Map.get(party, :name),
      description: Map.get(party, :description),
      active: Map.get(party, :active, true),
      campaign_id: Map.get(party, :campaign_id),
      faction_id: Map.get(party, :faction_id),
      juncture_id: Map.get(party, :juncture_id),
      faction:
        case Map.get(party, :faction) do
          %Ecto.Association.NotLoaded{} ->
            nil

          nil ->
            nil

          faction when is_map(faction) ->
            %{
              id: Map.get(faction, :id),
              name: Map.get(faction, :name)
            }

          _ ->
            nil
        end,
      juncture:
        case Map.get(party, :juncture) do
          %Ecto.Association.NotLoaded{} ->
            nil

          nil ->
            nil

          juncture when is_map(juncture) ->
            %{
              id: Map.get(juncture, :id),
              name: Map.get(juncture, :name)
            }

          _ ->
            nil
        end,
      created_at: Map.get(party, :created_at),
      updated_at: Map.get(party, :updated_at),
      image_url: Map.get(party, :image_url),
      entity_class: "Party"
    }
  end

  defp party_json_with_members(party) do
    base = party_json(party)

    {characters, vehicles} =
      if Ecto.assoc_loaded?(party.memberships) do
        party.memberships
        |> Enum.reduce({[], []}, fn membership, {chars, vehs} ->
          cond do
            membership.character_id && Ecto.assoc_loaded?(membership.character) ->
              character = %{
                id: membership.character.id,
                name: membership.character.name,
                category: "character",
                membership_id: membership.id,
                entity_class: "Character"
              }

              {[character | chars], vehs}

            membership.vehicle_id && Ecto.assoc_loaded?(membership.vehicle) ->
              vehicle = %{
                id: membership.vehicle.id,
                name: membership.vehicle.name,
                category: "vehicle",
                membership_id: membership.id,
                entity_class: "Vehicle"
              }

              {chars, [vehicle | vehs]}

            true ->
              {chars, vehs}
          end
        end)
      else
        {[], []}
      end

    base
    |> Map.put(:characters, Enum.reverse(characters))
    |> Map.put(:vehicles, Enum.reverse(vehicles))
  end
end
