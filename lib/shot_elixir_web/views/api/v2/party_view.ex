defmodule ShotElixirWeb.Api.V2.PartyView do

  def render("index.json", %{data: data}) do
    party_serializer =
      if data.is_autocomplete, do: &render_party_autocomplete/1, else: &render_party_index/1

    %{
      parties: Enum.map(data.parties, party_serializer),
      factions: data.factions,
      meta: data.meta,
      is_autocomplete: data.is_autocomplete
    }
  end

  def render("show.json", %{party: party}) do
    render_party_detail(party)
  end

  def render("error.json", %{changeset: changeset}) do
    %{errors: translate_errors(changeset)}
  end

  def render_party_index(party) do
    %{
      id: party.id,
      name: party.name,
      description: party.description,
      faction_id: party.faction_id,
      juncture_id: party.juncture_id,
      created_at: party.created_at,
      updated_at: party.updated_at,
      active: party.active,
      entity_class: "Party"
    }
  end

  def render_party_autocomplete(party) do
    %{
      id: party.id,
      name: party.name,
      entity_class: "Party"
    }
  end

  def render_party_detail(party) do
    base = %{
      id: party.id,
      name: party.name,
      description: party.description,
      faction_id: party.faction_id,
      juncture_id: party.juncture_id,
      created_at: party.created_at,
      updated_at: party.updated_at,
      active: party.active,
      campaign_id: party.campaign_id,
      entity_class: "Party"
    }

    # Add associations if loaded
    base
    |> add_if_loaded(:faction, party.faction)
    |> add_if_loaded(:juncture, party.juncture)
    |> add_if_loaded(:memberships, party.memberships)
  end

  defp add_if_loaded(base, key, association) do
    if Ecto.assoc_loaded?(association) do
      Map.put(base, key, render_association(key, association))
    else
      base
    end
  end

  defp render_association(:faction, nil), do: nil
  defp render_association(:faction, faction) do
    %{
      id: faction.id,
      name: faction.name,
      description: faction.description
    }
  end

  defp render_association(:juncture, nil), do: nil
  defp render_association(:juncture, juncture) do
    %{
      id: juncture.id,
      name: juncture.name,
      description: juncture.description
    }
  end

  defp render_association(:memberships, memberships) when is_list(memberships) do
    Enum.map(memberships, fn membership ->
      base = %{
        id: membership.id,
        party_id: membership.party_id,
        character_id: membership.character_id,
        vehicle_id: membership.vehicle_id
      }

      base = if Ecto.assoc_loaded?(membership.character) && membership.character do
        Map.put(base, :character, %{
          id: membership.character.id,
          name: membership.character.name,
          archetype: membership.character.archetype
        })
      else
        base
      end

      if Ecto.assoc_loaded?(membership.vehicle) && membership.vehicle do
        Map.put(base, :vehicle, %{
          id: membership.vehicle.id,
          name: membership.vehicle.name,
          vehicle_type: membership.vehicle.vehicle_type
        })
      else
        base
      end
    end)
  end

  defp render_association(_, association), do: association

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end