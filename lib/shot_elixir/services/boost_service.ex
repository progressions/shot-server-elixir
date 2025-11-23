defmodule ShotElixir.Services.BoostService do
  @moduledoc """
  Handles Boost actions in combat.
  """

  require Logger
  alias ShotElixir.Fights
  alias ShotElixir.Fights.Fight

  def apply_boost(%Fight{} = fight, params) do
    Logger.info("Applying boost for fight #{fight.id}")

    # Extract details from params if available
    description = params["description"] || "Boost action performed"

    # Record the event
    Fights.create_fight_event(%{
      "fight_id" => fight.id,
      "event_type" => "boost",
      "description" => description,
      "details" => Map.take(params, ["character_id", "cost", "target_id"])
    })

    # Return the fight (potentially reloaded if we modified it)
    fight
  end
end
