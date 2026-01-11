defmodule ShotElixirWeb.Api.V2.SoloController do
  @moduledoc """
  Controller for solo play API endpoints.

  Endpoints:
  - POST /api/v2/fights/:fight_id/solo/start - Start solo server
  - POST /api/v2/fights/:fight_id/solo/stop - Stop solo server
  - GET /api/v2/fights/:fight_id/solo/status - Get solo server status
  - POST /api/v2/fights/:fight_id/solo/advance - Advance to next NPC turn
  - POST /api/v2/fights/:fight_id/solo/action - Player takes action
  - POST /api/v2/fights/:fight_id/solo/roll_initiative - Roll initiative for all combatants
  """

  use ShotElixirWeb, :controller

  alias ShotElixir.Repo
  alias ShotElixir.Fights
  alias ShotElixir.Characters
  alias ShotElixir.Campaigns
  alias ShotElixir.Solo.Supervisor, as: SoloSupervisor
  alias ShotElixir.Solo.SoloFightServer
  alias ShotElixir.Services.DiceRoller

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  POST /api/v2/fights/:fight_id/solo/start
  Start the solo fight server for this fight.
  """
  def start(conn, %{"fight_id" => fight_id}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight(fight_id),
         :ok <- authorize_fight_access(fight, user),
         :ok <- validate_solo_mode(fight),
         {:ok, _pid} <- SoloSupervisor.start_solo_fight(fight_id) do
      conn
      |> put_status(:ok)
      |> json(%{
        success: true,
        message: "Solo server started",
        fight_id: fight_id
      })
    else
      {:error, {:already_started, _pid}} ->
        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          message: "Solo server already running",
          fight_id: fight_id
        })

      {:error, :not_solo_mode} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "Fight is not in solo mode"
        })

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          success: false,
          error: "Not authorized to access this fight"
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{
          success: false,
          error: "Fight not found"
        })

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: inspect(reason)
        })
    end
  end

  @doc """
  POST /api/v2/fights/:fight_id/solo/stop
  Stop the solo fight server for this fight.
  """
  def stop(conn, %{"fight_id" => fight_id}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight(fight_id),
         :ok <- authorize_fight_access(fight, user) do
      case SoloSupervisor.stop_solo_fight(fight_id) do
        :ok ->
          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            message: "Solo server stopped",
            fight_id: fight_id
          })

        {:error, :not_running} ->
          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            message: "Solo server was not running",
            fight_id: fight_id
          })
      end
    else
      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{success: false, error: "Not authorized to access this fight"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Fight not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  GET /api/v2/fights/:fight_id/solo/status
  Get the status of the solo fight server.
  """
  def status(conn, %{"fight_id" => fight_id}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight(fight_id),
         :ok <- authorize_fight_access(fight, user) do
      running = SoloSupervisor.solo_fight_running?(fight_id)

      state =
        if running do
          case SoloFightServer.get_state(fight_id) do
            {:ok, state} -> state
            _ -> nil
          end
        else
          nil
        end

      conn
      |> put_status(:ok)
      |> json(%{
        fight_id: fight_id,
        running: running,
        state:
          if(state,
            do: %{
              processing: state.processing,
              pc_character_ids: state.pc_character_ids,
              behavior_module: inspect(state.behavior_module)
            },
            else: nil
          )
      })
    else
      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{success: false, error: "Not authorized to access this fight"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Fight not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  POST /api/v2/fights/:fight_id/solo/advance
  Process the next NPC turn.
  """
  def advance(conn, %{"fight_id" => fight_id}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight(fight_id),
         :ok <- authorize_fight_access(fight, user) do
      case SoloFightServer.process_next_npc_turn(fight_id) do
        :ok ->
          conn
          |> put_status(:ok)
          |> json(%{
            success: true,
            message: "NPC turn processing triggered"
          })

        {:error, :not_running} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{
            success: false,
            error: "Solo server not running"
          })
      end
    else
      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{success: false, error: "Not authorized to access this fight"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Fight not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: inspect(reason)})
    end
  end

  @doc """
  POST /api/v2/fights/:fight_id/solo/action
  Player takes an action (attack, defend, stunt).
  """
  def player_action(conn, %{"fight_id" => fight_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    action_type = Map.get(params, "action_type", "attack")
    target_id = Map.get(params, "target_id")
    character_id = Map.get(params, "character_id")

    with {:ok, fight} <- get_fight(fight_id),
         :ok <- authorize_fight_access(fight, user),
         {:ok, result} <- execute_player_action(fight, character_id, action_type, target_id) do
      conn
      |> put_status(:ok)
      |> json(%{
        success: true,
        action: %{
          action_type: result.action_type,
          actor_name: result.actor_name,
          target_name: Map.get(result, :target_name),
          narrative: result.narrative,
          hit: result.hit,
          damage: result.damage,
          outcome: Map.get(result, :outcome),
          dice_result: Map.get(result, :dice_result)
        }
      })
    else
      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{success: false, error: "Not authorized to access this fight"})

      {:error, :forbidden_character} ->
        conn
        |> put_status(:forbidden)
        |> json(%{
          success: false,
          error: "Character is not a player character in this solo fight"
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Fight not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: inspect(reason)
        })
    end
  end

  @doc """
  POST /api/v2/fights/:fight_id/solo/roll_initiative
  Roll initiative for all combatants in the fight.
  Each character rolls 1d6 + Speed to determine starting shot.
  """
  def roll_initiative(conn, %{"fight_id" => fight_id}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, fight} <- get_fight(fight_id),
         :ok <- authorize_fight_access(fight, user),
         :ok <- validate_solo_mode(fight),
         {:ok, results} <- do_roll_initiative(fight) do
      conn
      |> put_status(:ok)
      |> json(%{
        success: true,
        message: "Initiative rolled for all combatants",
        results: results
      })
    else
      {:error, :not_solo_mode} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: "Fight is not in solo mode"
        })

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{success: false, error: "Not authorized to access this fight"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{success: false, error: "Fight not found"})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          success: false,
          error: inspect(reason)
        })
    end
  end

  # Private Functions

  defp get_fight(fight_id) do
    case Fights.get_fight(fight_id) do
      nil -> {:error, :not_found}
      fight -> {:ok, fight}
    end
  end

  defp validate_solo_mode(%{solo_mode: true}), do: :ok
  defp validate_solo_mode(_), do: {:error, :not_solo_mode}

  defp authorize_fight_access(fight, user) do
    campaign = Campaigns.get_campaign(fight.campaign_id)

    cond do
      is_nil(campaign) -> {:error, :not_found}
      campaign.user_id == user.id -> :ok
      user.admin -> :ok
      user.gamemaster && Campaigns.is_campaign_member?(campaign.id, user.id) -> :ok
      Campaigns.is_campaign_member?(campaign.id, user.id) -> :ok
      true -> {:error, :forbidden}
    end
  end

  defp execute_player_action(fight, character_id, action_type, target_id) do
    # Load fight with full associations
    fight = Fights.get_fight!(fight.id) |> Repo.preload(shots: [:character])

    # Validate that the character_id is in solo_player_character_ids
    player_character_ids = fight.solo_player_character_ids || []

    if character_id not in player_character_ids do
      {:error, :forbidden_character}
    else
      with {:ok, attacker_shot} <- find_shot_by_character(fight, character_id),
           {:ok, target_shot} <- find_shot_by_character(fight, target_id) do
        case action_type do
          "attack" -> execute_attack(fight, attacker_shot, target_shot)
          "defend" -> execute_defend(fight, attacker_shot)
          "stunt" -> execute_stunt(fight, attacker_shot, target_shot)
          _ -> {:error, :unknown_action_type}
        end
      end
    end
  end

  defp find_shot_by_character(fight, character_id) do
    case Enum.find(fight.shots, &(&1.character_id == character_id)) do
      nil -> {:error, :character_not_in_fight}
      shot -> {:ok, shot}
    end
  end

  defp execute_attack(fight, attacker_shot, target_shot) do
    attacker = attacker_shot.character
    target = target_shot.character
    swerve = DiceRoller.swerve()

    # Get attacker's main attack value
    attack_value = get_attack_value(attacker)
    defense = get_defense(target)

    # Calculate outcome
    action_result = attack_value + swerve.total
    outcome = action_result - defense

    # Calculate damage if hit
    {damage, smackdown, hit} =
      if outcome > 0 do
        base_damage = get_damage(attacker)
        toughness = get_toughness(target)
        smackdown = base_damage + outcome - toughness
        actual_damage = max(0, smackdown)
        {actual_damage, smackdown, true}
      else
        {0, 0, false}
      end

    # Build narrative
    narrative = build_attack_narrative(attacker, target, outcome, damage)

    # Apply damage if hit
    if hit && damage > 0 do
      apply_damage(target.id, damage)
    end

    # Spend shots (attacks cost 3 shots)
    spend_shots(attacker_shot, 3)

    # Build result
    result = %{
      action_type: :attack,
      actor_id: attacker.id,
      actor_name: attacker.name,
      target_id: target.id,
      target_name: target.name,
      narrative: narrative,
      dice_result: %{
        swerve: swerve.total,
        positives: swerve.positives.sum,
        negatives: swerve.negatives.sum,
        boxcars: swerve.boxcars,
        attack_value: attack_value,
        action_result: action_result,
        defense: defense
      },
      damage: damage,
      outcome: outcome,
      smackdown: smackdown,
      hit: hit
    }

    # Log fight event
    log_fight_event(fight, result)

    # Broadcast to clients
    broadcast_action(fight, result)

    {:ok, result}
  end

  defp execute_defend(fight, defender_shot) do
    defender = defender_shot.character

    # Spend shots (defend costs 1 shot)
    spend_shots(defender_shot, 1)

    result = %{
      action_type: :defend,
      actor_id: defender.id,
      actor_name: defender.name,
      narrative: "#{defender.name} takes a defensive stance.",
      hit: false,
      damage: 0
    }

    log_fight_event(fight, result)
    broadcast_action(fight, result)

    {:ok, result}
  end

  defp execute_stunt(fight, actor_shot, _target_shot) do
    actor = actor_shot.character

    # Spend shots (stunts cost 3 shots)
    spend_shots(actor_shot, 3)

    result = %{
      action_type: :stunt,
      actor_id: actor.id,
      actor_name: actor.name,
      narrative: "#{actor.name} performs a dramatic stunt!",
      hit: false,
      damage: 0
    }

    log_fight_event(fight, result)
    broadcast_action(fight, result)

    {:ok, result}
  end

  defp get_attack_value(character) do
    av = character.action_values || %{}
    main_attack = Map.get(av, "MainAttack", "Guns")
    Map.get(av, main_attack, 0) |> to_integer()
  end

  defp get_defense(character) do
    character.defense ||
      Map.get(character.action_values || %{}, "Defense", 0) |> to_integer()
  end

  defp get_toughness(character) do
    Map.get(character.action_values || %{}, "Toughness", 0) |> to_integer()
  end

  defp get_damage(character) do
    Map.get(character.action_values || %{}, "Damage", 7) |> to_integer()
  end

  defp to_integer(val) when is_integer(val), do: val
  defp to_integer(val) when is_binary(val), do: String.to_integer(val)
  defp to_integer(_), do: 0

  defp build_attack_narrative(attacker, target, outcome, damage) do
    if outcome > 0 do
      "#{attacker.name} attacks #{target.name} and hits for #{damage} damage!"
    else
      "#{attacker.name} attacks #{target.name} but misses!"
    end
  end

  defp apply_damage(target_id, damage) do
    case Characters.get_character(target_id) do
      nil ->
        :ok

      character ->
        current_wounds = Map.get(character.action_values || %{}, "Wounds", 0) |> to_integer()
        new_wounds = current_wounds + damage

        Characters.update_character(character, %{
          action_values: Map.put(character.action_values || %{}, "Wounds", new_wounds)
        })
    end
  end

  defp spend_shots(shot, cost) do
    new_shot_value = max(0, (shot.shot || 0) - cost)
    Fights.update_shot(shot, %{"shot" => new_shot_value})
  end

  defp log_fight_event(fight, result) do
    event_attrs = %{
      fight_id: fight.id,
      event_type: "solo_player_action",
      description: result.narrative,
      details: %{
        action_type: result.action_type,
        actor_id: result.actor_id,
        actor_name: result.actor_name,
        target_id: Map.get(result, :target_id),
        target_name: Map.get(result, :target_name),
        outcome: Map.get(result, :outcome),
        damage: result.damage,
        hit: result.hit,
        dice_result: Map.get(result, :dice_result)
      }
    }

    Fights.create_fight_event(event_attrs)
  end

  defp broadcast_action(fight, result) do
    Phoenix.PubSub.broadcast(
      ShotElixir.PubSub,
      "campaign:#{fight.campaign_id}",
      {:solo_player_action,
       %{
         fight_id: fight.id,
         action: result
       }}
    )
  end

  defp do_roll_initiative(fight) do
    # Load fight with shots and characters
    fight = Fights.get_fight!(fight.id) |> Repo.preload(shots: [:character, :vehicle])

    # Roll initiative for each shot
    results =
      Enum.map(fight.shots, fn shot ->
        entity = shot.character || shot.vehicle

        if entity do
          # Get Speed from action_values, default to 0
          speed = get_speed(entity)

          # Roll 1d6 + Speed
          roll = DiceRoller.die_roll()
          new_shot_value = roll + speed

          # Update the shot
          case Fights.update_shot(shot, %{"shot" => new_shot_value}) do
            {:ok, _updated_shot} ->
              %{
                name: entity.name,
                roll: roll,
                speed: speed,
                shot: new_shot_value
              }

            {:error, _} ->
              %{
                name: entity.name,
                roll: roll,
                speed: speed,
                shot: shot.shot,
                error: "Failed to update"
              }
          end
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.shot, :desc)

    # Log initiative event
    log_initiative_event(fight, results)

    # Broadcast initiative rolled
    broadcast_initiative(fight, results)

    {:ok, results}
  end

  defp get_speed(entity) do
    av = entity.action_values || %{}
    Map.get(av, "Speed", 0) |> to_integer()
  end

  defp log_initiative_event(fight, results) do
    description =
      results
      |> Enum.map(fn r -> "#{r.name}: #{r.shot} (#{r.roll} + #{r.speed})" end)
      |> Enum.join(", ")

    event_attrs = %{
      fight_id: fight.id,
      event_type: "solo_initiative",
      description: "Initiative rolled: #{description}",
      details: %{
        results: results
      }
    }

    Fights.create_fight_event(event_attrs)
  end

  defp broadcast_initiative(fight, results) do
    Phoenix.PubSub.broadcast(
      ShotElixir.PubSub,
      "campaign:#{fight.campaign_id}",
      {:solo_initiative,
       %{
         fight_id: fight.id,
         results: results
       }}
    )
  end
end
