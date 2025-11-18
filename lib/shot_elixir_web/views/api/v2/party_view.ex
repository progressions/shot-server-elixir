defmodule ShotElixirWeb.Api.V2.PartyView do
  def render("index.json", %{parties: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{parties: parties, meta: meta, is_autocomplete: is_autocomplete} ->
        party_serializer =
          if is_autocomplete, do: &render_party_autocomplete/1, else: &render_party/1

        %{
          parties: Enum.map(parties, party_serializer),
          meta: meta
        }

      %{parties: parties, meta: meta} ->
        %{
          parties: Enum.map(parties, &render_party/1),
          meta: meta
        }

      parties when is_list(parties) ->
        # Legacy format for backward compatibility
        %{
          parties: Enum.map(parties, &render_party/1),
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(parties),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{party: party}) do
    %{
      party: render_party(party)
    }
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  defp render_party(party) do
    %{
      id: party.id,
      name: party.name,
      description: party.description,
      campaign_id: party.campaign_id,
      created_at: party.created_at,
      updated_at: party.updated_at,
      image_url: party.image_url
    }
  end

  defp render_party_autocomplete(party) do
    %{
      id: party.id,
      name: party.name,
      entity_class: "Party"
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