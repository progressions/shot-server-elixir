defmodule ShotElixir.Services.BoostService do
  @moduledoc """
  Handles Boost actions in combat.
  """

  require Logger
  alias ShotElixir.{Repo, Fights, Effects, Characters}
  alias ShotElixir.Fights.{Fight, Shot}
  alias ShotElixir.Characters.Character

  @boost_cost 3

  @boost_values %{
    "attack" => %{base: 1, fortune: 2},
    "defense" => %{base: 3, fortune: 5}
  }

  def apply_boost(%Fight{} = fight, params) do
    Logger.info("Applying boost for fight #{fight.id}")

    Repo.transaction(fn ->
      booster_id = params["booster_id"] || params["character_id"]
      target_id = params["target_id"]
      boost_type = params["boost_type"] || "attack"
      use_fortune = params["use_fortune"] || false

      with {:ok, booster_shot} <- get_shot_by_character(fight, booster_id),
           {:ok, target_shot} <- get_shot_by_character(fight, target_id) do
        booster = Repo.preload(booster_shot, :character).character
        target = Repo.preload(target_shot, :character).character

        can_use_fortune = is_pc?(booster) && use_fortune
        current_fortune = if can_use_fortune, do: get_av(booster, "Fortune"), else: 0

        # Check fortune
        if can_use_fortune && current_fortune < 1 do
          Repo.rollback("Insufficient Fortune")
        end

        # Deduct shots
        new_shot = (booster_shot.shot || 0) - @boost_cost

        case Fights.update_shot(booster_shot, %{shot: new_shot}) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

        # Deduct fortune
        if can_use_fortune do
          current_values = booster.action_values || %{}
          updated_values = Map.put(current_values, "Fortune", current_fortune - 1)

          case Characters.update_character(booster, %{
                 "action_values" => updated_values
               }) do
            {:ok, _} -> :ok
            {:error, reason} -> Repo.rollback(reason)
          end
        end

        # Calculate value
        values = @boost_values[boost_type] || @boost_values["attack"]
        boost_value = if can_use_fortune, do: values.fortune, else: values.base

        # Create Effect
        effect_name = if boost_type == "attack", do: "Attack Boost", else: "Defense Boost"
        effect_name = if can_use_fortune, do: "#{effect_name} (Fortune)", else: effect_name

        action_value =
          if boost_type == "attack" do
            get_av(target, "MainAttack") || "Guns"
          else
            "Defense"
          end

        case Effects.create_character_effect(%{
               name: effect_name,
               description: "Boost from #{booster.name}",
               severity: "info",
               action_value: action_value,
               change: "+#{boost_value}",
               character_id: target.id,
               shot_id: target_shot.id
             }) do
          {:ok, _} -> :ok
          {:error, reason} -> Repo.rollback(reason)
        end

        # Create Event
        case Fights.create_fight_event(
               %{
                 "fight_id" => fight.id,
                 "event_type" => "boost",
                 "description" =>
                   "#{booster.name} boosted #{target.name}'s #{boost_type} (+#{boost_value})",
                 "details" => %{
                   "booster_id" => booster.id,
                   "target_id" => target.id,
                   "boost_type" => boost_type,
                   "boost_value" => boost_value,
                   "fortune_used" => can_use_fortune
                 }
               },
               broadcast: false
             ) do
          {:ok, _} ->
            fight

          {:error, reason} ->
            Repo.rollback(reason)
        end
      else
        {:error, reason} -> Repo.rollback(reason)
        nil -> Repo.rollback("Missing parameters or resources")
      end
    end)
    |> case do
      {:ok, fight} -> Fights.touch_fight(fight)
      error -> error
    end
  end

  defp get_shot_by_character(fight, character_id) do
    case Repo.get_by(Shot, fight_id: fight.id, character_id: character_id) do
      nil -> {:error, "Shot not found for character #{character_id}"}
      shot -> {:ok, shot}
    end
  end

  defp is_pc?(%Character{action_values: action_values}) when is_map(action_values) do
    action_values["Type"] == "PC"
  end

  defp is_pc?(_), do: false

  defp get_av(%Character{action_values: action_values}, key) when is_map(action_values) do
    action_values[key] || 0
  end

  defp get_av(_, _), do: 0
end
