defmodule ShotElixirWeb.Api.V2.SoloController do
  @moduledoc """
  Controller for solo play API endpoints.

  Endpoints:
  - POST /api/v2/fights/:fight_id/solo/start - Start solo server
  - POST /api/v2/fights/:fight_id/solo/stop - Stop solo server
  - GET /api/v2/fights/:fight_id/solo/status - Get solo server status
  - POST /api/v2/fights/:fight_id/solo/advance - Advance to next NPC turn
  - POST /api/v2/fights/:fight_id/solo/action - Player takes action
  """

  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Solo.Supervisor, as: SoloSupervisor
  alias ShotElixir.Solo.SoloFightServer

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  POST /api/v2/fights/:fight_id/solo/start
  Start the solo fight server for this fight.
  """
  def start(conn, %{"fight_id" => fight_id}) do
    with {:ok, fight} <- get_fight(fight_id),
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
  end

  @doc """
  GET /api/v2/fights/:fight_id/solo/status
  Get the status of the solo fight server.
  """
  def status(conn, %{"fight_id" => fight_id}) do
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
      state: if(state, do: %{
        processing: state.processing,
        pc_character_ids: state.pc_character_ids,
        behavior_module: inspect(state.behavior_module)
      }, else: nil)
    })
  end

  @doc """
  POST /api/v2/fights/:fight_id/solo/advance
  Process the next NPC turn.
  """
  def advance(conn, %{"fight_id" => fight_id}) do
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
  end

  @doc """
  POST /api/v2/fights/:fight_id/solo/action
  Player takes an action (attack, defend, stunt).
  """
  def action(conn, %{"fight_id" => fight_id} = params) do
    action_type = Map.get(params, "action_type", "attack")
    target_id = Map.get(params, "target_id")
    character_id = Map.get(params, "character_id")

    with {:ok, fight} <- get_fight(fight_id),
         {:ok, _result} <- execute_player_action(fight, character_id, action_type, target_id) do
      conn
      |> put_status(:ok)
      |> json(%{
        success: true,
        message: "Action executed"
      })
    else
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
      nil -> {:error, :fight_not_found}
      fight -> {:ok, fight}
    end
  end

  defp validate_solo_mode(%{solo_mode: true}), do: :ok
  defp validate_solo_mode(_), do: {:error, :not_solo_mode}

  defp execute_player_action(_fight, _character_id, _action_type, _target_id) do
    # TODO: Implement player action execution
    # This will handle the player's turn, roll dice, apply damage, etc.
    {:ok, %{}}
  end
end
