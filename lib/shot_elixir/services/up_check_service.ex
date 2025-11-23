defmodule ShotElixir.Services.UpCheckService do
  @moduledoc """
  Handles Up Check actions (recovery rolls).
  """

  require Logger
  alias ShotElixir.Fights
  alias ShotElixir.Fights.Fight

  def apply_up_check(%Fight{} = fight, params) do
    Logger.info("Applying up check for fight #{fight.id}")

    # Record the event
    case Fights.create_fight_event(%{
           "fight_id" => fight.id,
           "event_type" => "up_check",
           "description" => "Up check performed",
           "details" => Map.take(params, ["character_id", "result", "success"])
         }) do
      {:ok, _event} -> {:ok, fight}
      error -> error
    end
  end
end
