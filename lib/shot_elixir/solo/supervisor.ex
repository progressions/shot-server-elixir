defmodule ShotElixir.Solo.Supervisor do
  @moduledoc """
  Supervisor for solo play components.

  Manages:
  - Registry for looking up SoloFightServer processes by fight_id
  - DynamicSupervisor for spawning SoloFightServer processes
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Registry for looking up solo fight servers by fight_id
      {Registry, keys: :unique, name: ShotElixir.Solo.Registry},

      # DynamicSupervisor for spawning solo fight servers
      {DynamicSupervisor, name: ShotElixir.Solo.DynamicSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @doc """
  Start a solo fight server for the given fight.
  """
  def start_solo_fight(fight_id) do
    DynamicSupervisor.start_child(
      ShotElixir.Solo.DynamicSupervisor,
      {ShotElixir.Solo.SoloFightServer, fight_id}
    )
  end

  @doc """
  Stop a solo fight server for the given fight.
  """
  def stop_solo_fight(fight_id) do
    ShotElixir.Solo.SoloFightServer.stop(fight_id)
  end

  @doc """
  Check if a solo fight server is running.
  """
  def solo_fight_running?(fight_id) do
    ShotElixir.Solo.SoloFightServer.running?(fight_id)
  end
end
