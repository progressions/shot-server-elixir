defmodule ShotElixir.Solo.SoloFightServer do
  @moduledoc """
  GenServer that manages solo play for a single fight.

  Responsibilities:
  - Monitor shot counter changes via PubSub
  - Determine when NPCs should act
  - Call behavior provider for NPC decisions
  - Execute actions and apply damage
  - Log fight events
  - Broadcast updates to clients
  """

  use GenServer
  require Logger

  alias ShotElixir.Repo
  alias ShotElixir.Fights
  alias ShotElixir.Solo.{Behavior, Combat, SimpleBehavior}

  @registry ShotElixir.Solo.Registry

  # Client API

  @doc """
  Start a solo fight server for the given fight.
  """
  def start_link(fight_id) do
    GenServer.start_link(__MODULE__, fight_id, name: via_tuple(fight_id))
  end

  @doc """
  Stop the solo fight server for the given fight.
  """
  def stop(fight_id) do
    case Registry.lookup(@registry, fight_id) do
      [{pid, _}] -> GenServer.stop(pid, :normal)
      [] -> {:error, :not_running}
    end
  end

  @doc """
  Check if a solo fight server is running for the given fight.
  """
  def running?(fight_id) do
    case Registry.lookup(@registry, fight_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc """
  Get the current state of the solo fight server.
  """
  def get_state(fight_id) do
    case Registry.lookup(@registry, fight_id) do
      [{pid, _}] -> GenServer.call(pid, :get_state)
      [] -> {:error, :not_running}
    end
  end

  @doc """
  Trigger processing of the next NPC turn.
  Called when the player advances the shot counter or completes their turn.
  """
  def process_next_npc_turn(fight_id) do
    case Registry.lookup(@registry, fight_id) do
      [{pid, _}] -> GenServer.cast(pid, :process_next_npc_turn)
      [] -> {:error, :not_running}
    end
  end

  @doc """
  Manually trigger an NPC action (for testing/debugging).
  """
  def trigger_npc_action(fight_id, character_id) do
    case Registry.lookup(@registry, fight_id) do
      [{pid, _}] -> GenServer.call(pid, {:trigger_npc_action, character_id})
      [] -> {:error, :not_running}
    end
  end

  # Server Callbacks

  @impl true
  def init(fight_id) do
    Logger.info("[SoloFightServer] Starting for fight #{fight_id}")

    # Load fight with associations
    case load_fight(fight_id) do
      {:ok, fight} ->
        # Subscribe to fight updates
        Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{fight.campaign_id}")

        state = %{
          fight_id: fight_id,
          campaign_id: fight.campaign_id,
          pc_character_ids: fight.solo_player_character_ids || [],
          behavior_module: get_behavior_module(fight.solo_behavior_type),
          processing: false
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call({:trigger_npc_action, character_id}, _from, state) do
    result = do_npc_action(state, character_id)
    {:reply, result, state}
  end

  @impl true
  def handle_cast(:process_next_npc_turn, %{processing: true} = state) do
    # Already processing, ignore
    {:noreply, state}
  end

  @impl true
  def handle_cast(:process_next_npc_turn, state) do
    state = %{state | processing: true}

    case find_next_npc_to_act(state) do
      {:ok, npc_shot} ->
        Logger.info("[SoloFightServer] NPC #{npc_shot.character.name} acting")
        do_npc_action(state, npc_shot.character_id)
        {:noreply, %{state | processing: false}}

      {:error, :no_npc_turn} ->
        Logger.debug("[SoloFightServer] No NPC turn to process")
        {:noreply, %{state | processing: false}}

      {:error, reason} ->
        Logger.error("[SoloFightServer] Error finding next NPC: #{inspect(reason)}")
        {:noreply, %{state | processing: false}}
    end
  end

  @impl true
  def handle_info({:fight_update, _payload}, state) do
    # Could be used to react to fight state changes
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private Functions

  defp via_tuple(fight_id) do
    {:via, Registry, {@registry, fight_id}}
  end

  defp load_fight(fight_id) do
    fight =
      Fights.get_fight!(fight_id)
      |> Repo.preload([
        :campaign,
        :fight_events,
        shots: [:character, :vehicle]
      ])

    {:ok, fight}
  rescue
    Ecto.NoResultsError -> {:error, :fight_not_found}
  end

  defp get_behavior_module("ai"), do: ShotElixir.Solo.AiBehavior
  defp get_behavior_module(_), do: SimpleBehavior

  defp find_next_npc_to_act(state) do
    case load_fight(state.fight_id) do
      {:ok, fight} ->
        # Find shots ordered by shot descending
        # The highest shot that belongs to an NPC (not in pc_character_ids)
        # and hasn't acted yet this sequence
        npc_shot =
          fight.shots
          |> Enum.filter(fn shot ->
            shot.character_id != nil &&
              shot.character_id not in state.pc_character_ids &&
              shot.shot != nil &&
              shot.shot > 0
          end)
          |> Enum.sort_by(& &1.shot, :desc)
          |> List.first()

        if npc_shot do
          {:ok, npc_shot}
        else
          {:error, :no_npc_turn}
        end

      error ->
        error
    end
  end

  defp do_npc_action(state, character_id) do
    with {:ok, fight} <- load_fight(state.fight_id),
         {:ok, acting_shot} <- find_shot_by_character(fight, character_id),
         context <- Behavior.build_context(fight, acting_shot, state.pc_character_ids),
         {:ok, action_result} <- state.behavior_module.determine_action(context) do
      # Apply the action result
      apply_action_result(fight, acting_shot, action_result)
      {:ok, action_result}
    else
      {:error, reason} = error ->
        Logger.error("[SoloFightServer] NPC action failed: #{inspect(reason)}")
        error
    end
  end

  defp find_shot_by_character(fight, character_id) do
    case Enum.find(fight.shots, &(&1.character_id == character_id)) do
      nil -> {:error, :shot_not_found}
      shot -> {:ok, shot}
    end
  end

  defp apply_action_result(fight, acting_shot, action_result) do
    # Spend shots for the action (cost varies by action type via Combat.get_shot_cost/1)
    shot_cost = Combat.get_shot_cost(action_result.action_type)
    spend_shots(acting_shot, shot_cost)

    # Apply damage to target if hit
    if action_result.hit && action_result.target_id && action_result.damage > 0 do
      case apply_damage(action_result.target_id, action_result.damage) do
        :ok ->
          :ok

        :error ->
          Logger.warning(
            "[SoloFightServer] Damage application failed for target #{action_result.target_id}"
          )
      end
    end

    # Log the fight event
    log_fight_event(fight, acting_shot, action_result)

    # Broadcast the update
    broadcast_action(fight, action_result)

    :ok
  end

  defp spend_shots(shot, cost) do
    new_shot_value = max(0, (shot.shot || 0) - cost)
    Logger.info("[SoloFightServer] Spending #{cost} shots: #{shot.shot} -> #{new_shot_value}")
    Fights.update_shot(shot, %{"shot" => new_shot_value})
  end

  defp apply_damage(target_character_id, damage) do
    case ShotElixir.Characters.get_character(target_character_id) do
      nil ->
        Logger.warning("[SoloFightServer] Target character not found: #{target_character_id}")
        :error

      character ->
        current_wounds = Map.get(character.action_values || %{}, "Wounds", 0)
        new_wounds = current_wounds + damage

        attrs = %{
          action_values: Map.put(character.action_values || %{}, "Wounds", new_wounds)
        }

        case ShotElixir.Characters.update_character(character, attrs) do
          {:ok, _updated_character} ->
            :ok

          {:error, reason} ->
            Logger.error(
              "[SoloFightServer] Failed to apply damage to character #{character.id}: #{inspect(reason)}"
            )

            :error
        end
    end
  end

  defp log_fight_event(fight, acting_shot, action_result) do
    event_attrs = %{
      fight_id: fight.id,
      event_type: "solo_npc_action",
      description: action_result.narrative,
      details: %{
        action_type: action_result.action_type,
        actor_id: acting_shot.character_id,
        actor_name: acting_shot.character.name,
        target_id: action_result.target_id,
        outcome: action_result.outcome,
        damage: action_result.damage,
        hit: action_result.hit,
        dice_result: action_result.dice_result
      }
    }

    Fights.create_fight_event(event_attrs)
  end

  defp broadcast_action(fight, action_result) do
    Phoenix.PubSub.broadcast(
      ShotElixir.PubSub,
      "campaign:#{fight.campaign_id}",
      {:solo_npc_action,
       %{
         fight_id: fight.id,
         action: action_result
       }}
    )
  end
end
