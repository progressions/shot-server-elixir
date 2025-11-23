defmodule ShotElixir.Services.ChaseActionService do
  @moduledoc """
  Handles vehicle chase actions.
  """

  require Logger
  alias ShotElixir.Fights
  alias ShotElixir.Fights.Fight

  def apply_chase_action(%Fight{} = fight, vehicle_updates) do
    Logger.info("Applying chase action for fight #{fight.id}")

    # Record the event
    case Fights.create_fight_event(%{
           "fight_id" => fight.id,
           "event_type" => "chase_action",
           "description" => "Chase action performed with #{length(vehicle_updates)} updates",
           "details" => %{"updates_count" => length(vehicle_updates)}
         }) do
      {:ok, _event} -> {:ok, fight}
      error -> error
    end
  end
end
