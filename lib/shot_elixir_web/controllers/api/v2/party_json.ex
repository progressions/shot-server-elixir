defmodule ShotElixirWeb.Api.V2.PartyJSON do
  def index(%{parties: parties}) do
    %{parties: Enum.map(parties, &party_json/1)}
  end

  def show(%{party: party}) do
    %{party: party_json_with_members(party)}
  end

  def error(%{changeset: changeset}) do
    %{
      errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    }
  end

  defp party_json(party) do
    %{
      id: party.id,
      name: party.name,
      description: party.description,
      active: party.active,
      campaign_id: party.campaign_id,
      faction_id: party.faction_id,
      juncture_id: party.juncture_id,
      faction: if Ecto.assoc_loaded?(party.faction) && party.faction do
        %{
          id: party.faction.id,
          name: party.faction.name
        }
      else
        nil
      end,
      juncture: if Ecto.assoc_loaded?(party.juncture) && party.juncture do
        %{
          id: party.juncture.id,
          name: party.juncture.name
        }
      else
        nil
      end,
      created_at: party.created_at,
      updated_at: party.updated_at
    }
  end

  defp party_json_with_members(party) do
    base = party_json(party)

    {characters, vehicles} = if Ecto.assoc_loaded?(party.memberships) do
      party.memberships
      |> Enum.reduce({[], []}, fn membership, {chars, vehs} ->
        cond do
          membership.character_id && Ecto.assoc_loaded?(membership.character) ->
            character = %{
              id: membership.character.id,
              name: membership.character.name,
              category: "character",
              membership_id: membership.id
            }
            {[character | chars], vehs}

          membership.vehicle_id && Ecto.assoc_loaded?(membership.vehicle) ->
            vehicle = %{
              id: membership.vehicle.id,
              name: membership.vehicle.name,
              category: "vehicle",
              membership_id: membership.id
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