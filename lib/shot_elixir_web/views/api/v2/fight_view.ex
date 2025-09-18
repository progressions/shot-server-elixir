defmodule ShotElixirWeb.Api.V2.FightView do
  def render("index.json", %{fights: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{fights: fights, seasons: seasons, meta: meta, is_autocomplete: is_autocomplete} ->
        fight_serializer =
          if is_autocomplete, do: &render_fight_autocomplete/1, else: &render_fight/1

        %{
          fights: Enum.map(fights, fight_serializer),
          seasons: seasons,
          meta: meta
        }

      %{fights: fights, seasons: seasons, meta: meta} ->
        %{
          fights: Enum.map(fights, &render_fight/1),
          seasons: seasons,
          meta: meta
        }

      fights when is_list(fights) ->
        # Legacy format for backward compatibility
        %{
          fights: Enum.map(fights, &render_fight/1),
          seasons: [],
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(fights),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{fight: fight}) do
    %{fight: render_fight_detail(fight)}
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

  defp render_fight(fight) do
    %{
      id: fight.id,
      name: fight.name,
      description: fight.description,
      campaign_id: fight.campaign_id,
      started_at: fight.started_at,
      ended_at: fight.ended_at,
      active: fight.active,
      season: fight.season,
      session: fight.session,
      created_at: fight.created_at,
      updated_at: fight.updated_at
    }
  end

  defp render_fight_autocomplete(fight) do
    %{
      id: fight.id,
      name: fight.name,
      active: fight.active
    }
  end

  defp render_fight_detail(fight) do
    base = render_fight(fight)

    # Add associations if they're loaded
    shots =
      case Map.get(fight, :shots) do
        %Ecto.Association.NotLoaded{} -> []
        shots -> Enum.map(shots, &render_shot/1)
      end

    Map.merge(base, %{
      shots: shots
    })
  end

  defp render_shot(shot) do
    %{
      id: shot.id,
      shot: shot.shot,
      character_id: shot.character_id,
      vehicle_id: shot.vehicle_id,
      acted: shot.acted,
      sequence: shot.sequence
    }
  end
end
