defmodule ShotElixir.Discord.FightPoster do
  @moduledoc """
  Generates markdown-formatted fight information for Discord.
  Matches the Rails FightPoster service output format exactly.
  """
  import Ecto.Query
  alias ShotElixir.Repo
  alias ShotElixir.Fights.{Fight, Shot}
  alias ShotElixir.Effects.{Effect, CharacterEffect}
  alias ShotElixir.Characters.Character
  alias ShotElixir.Vehicles.Vehicle

  @severities %{
    "info" => "",
    "error" => "- ",
    "success" => "+ ",
    "warning" => "! "
  }

  # Sort order for character types (matches Rails Fight::SORT_ORDER)
  @sort_order ["Uber-Boss", "Boss", "PC", "Ally", "Featured Foe", "Mook"]

  @doc """
  Generates markdown representation of a fight for Discord display.
  Returns the same format as Rails FightPoster.show(fight).
  """
  def shots(fight_id) when is_binary(fight_id) do
    fight = load_fight(fight_id)
    show(fight)
  end

  @doc """
  Generate the full markdown display for a fight.
  """
  def show(%Fight{} = fight) do
    description = clean_description(fight.description)
    active_effects = get_active_effects(fight)
    shot_order = build_shot_order(fight)
    latest_event = get_latest_event(fight)

    """
    # #{fight.name}
    #{if description != "", do: description <> "\n", else: ""}
    ## Sequence #{fight.sequence || 0}
    #{format_active_effects(active_effects)}#{format_shot_order(shot_order, fight)}
    #{latest_event}
    """
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  # Load fight with all necessary associations
  defp load_fight(fight_id) do
    Fight
    |> where([f], f.id == ^fight_id)
    |> preload([
      :effects,
      :fight_events,
      shots: [
        :character,
        :vehicle,
        :character_effects,
        :location_ref,
        driver: :character,
        driving: :vehicle
      ]
    ])
    |> Repo.one!()
  end

  # Clean HTML description to markdown
  defp clean_description(nil), do: ""
  defp clean_description(""), do: ""

  defp clean_description(description) do
    description
    # Convert HTML to text/markdown
    |> String.replace(~r/<p>/, "")
    |> String.replace(~r/<\/p>/, "\n")
    |> String.replace(~r/<strong>/, "**")
    |> String.replace(~r/<\/strong>/, "**")
    |> String.replace(~r/<em>/, "*")
    |> String.replace(~r/<\/em>/, "*")
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    # Clean mention markup: [@Name](/path) -> Name
    |> String.replace(~r/\[@([^\]]+)\]\(\/[^)]+\)/, "\\1")
    |> String.trim()
  end

  # Get active fight-level effects
  defp get_active_effects(%Fight{effects: effects, sequence: sequence} = fight) do
    current_shot = get_current_shot(fight)

    effects
    |> Enum.filter(fn effect ->
      current_shot > 0 &&
        ((sequence == effect.start_sequence && current_shot <= effect.start_shot) ||
           (sequence == effect.end_sequence && current_shot > effect.end_shot))
    end)
    |> Enum.sort_by(& &1.severity)
  end

  defp get_current_shot(%Fight{shots: shots}) do
    shots
    |> Enum.map(& &1.shot)
    |> Enum.reject(&is_nil/1)
    |> Enum.max(fn -> 0 end)
  end

  # Format fight-level effects section
  defp format_active_effects([]), do: ""

  defp format_active_effects(effects) do
    effect_lines = Enum.map(effects, &format_fight_effect/1) |> Enum.join("\n")

    """
    ```diff
    #{effect_lines}
    ```
    """
  end

  defp format_fight_effect(%Effect{} = effect) do
    name = effect.name || ""

    description =
      if effect.description && effect.description != "", do: " #{effect.description}", else: ""

    status = Map.get(@severities, effect.severity || "info", "")

    name = if description != "", do: "#{name}:", else: name

    "#{status}#{name}#{description} (until sequence #{effect.end_sequence}, shot #{effect.end_shot})"
  end

  # Build shot order - groups shots by shot number and sorts
  defp build_shot_order(%Fight{shots: shots}) do
    shots
    |> Enum.filter(fn shot -> shot.shot != nil end)
    |> Enum.group_by(& &1.shot)
    |> Enum.sort_by(fn {shot, _} -> -shot end)
    |> Enum.map(fn {shot, shot_records} ->
      sorted_records =
        shot_records
        |> Enum.sort_by(&shot_sort_order/1)
        |> expand_driver_vehicle_pairs()

      {shot, sorted_records}
    end)
    |> Enum.reject(fn {_, records} -> Enum.empty?(records) end)
  end

  # Sort order for shots - characters first, then vehicles, by type priority and speed
  defp shot_sort_order(%Shot{character: %Character{} = char}) do
    char_type = get_in(char.action_values, ["Type"]) || "PC"
    speed = (get_in(char.action_values, ["Speed"]) || 0) - (char.impairments || 0)
    type_index = Enum.find_index(@sort_order, &(&1 == char_type)) || 99

    {0, type_index, -speed, String.downcase(char.name || "")}
  end

  defp shot_sort_order(%Shot{vehicle: %Vehicle{} = vehicle}) do
    vehicle_type = get_in(vehicle.action_values, ["Type"]) || "PC"
    accel = (get_in(vehicle.action_values, ["Acceleration"]) || 0) - (vehicle.impairments || 0)
    type_index = Enum.find_index(@sort_order, &(&1 == vehicle_type)) || 99

    {1, type_index, -accel, String.downcase(vehicle.name || "")}
  end

  defp shot_sort_order(_), do: {99, 99, 0, ""}

  # Expand driver/vehicle pairs - when a character is driving a vehicle, show both
  defp expand_driver_vehicle_pairs(shots) do
    Enum.flat_map(shots, fn shot ->
      cond do
        # Character driving a vehicle - show character then vehicle
        shot.driving_id != nil && shot.driving != nil ->
          [{:character, shot}, {:vehicle, shot.driving, shot}]

        # Regular character
        shot.character_id != nil ->
          [{:character, shot}]

        # Vehicle not being driven (driver_id is nil)
        shot.vehicle_id != nil && shot.driver_id == nil ->
          [{:vehicle, shot, shot}]

        true ->
          []
      end
    end)
  end

  # Format the shot order section
  defp format_shot_order(shot_order, fight) do
    shot_order
    |> Enum.map(fn {shot, records} ->
      header = "## Shot #{shot}"

      entries =
        records
        |> Enum.map(fn
          {:character, shot_record} ->
            format_character(shot_record, fight)

          {:vehicle, vehicle_shot, shot_record} ->
            format_vehicle(vehicle_shot, shot_record, fight)
        end)
        |> Enum.join("")

      "#{header}\n#{entries}"
    end)
    |> Enum.join("")
  end

  # Format a character entry
  defp format_character(%Shot{character: char} = shot, _fight) do
    location_name = get_location_name(shot)
    location_str = if location_name && location_name != "", do: " (#{location_name})", else: ""
    wounds_impairments = wounds_and_impairments(char)

    action_values_line = format_character_action_values(char)
    effects_block = format_character_effects(shot, char)

    if good_guy?(char) do
      wounds_line = if wounds_impairments != "", do: " #{wounds_impairments}\n", else: ""
      "- **#{char.name}**#{location_str} \n#{wounds_line} #{action_values_line}\n#{effects_block}"
    else
      "- **#{char.name}**#{location_str} \n"
    end
  end

  # Format a vehicle entry
  defp format_vehicle(
         %Shot{vehicle: vehicle} = _vehicle_shot,
         shot,
         _fight
       ) do
    location_name = get_location_name(shot)
    location_str = if location_name && location_name != "", do: " (#{location_name})", else: ""

    pursuer_evader =
      if get_in(vehicle.action_values, ["Pursuer"]) == "true", do: "Pursuer", else: "Evader"

    position = get_in(vehicle.action_values, ["Position"]) || ""

    if good_guy_vehicle?(vehicle) do
      chase_line = chase_points_and_impairments(vehicle)
      action_values_line = format_vehicle_action_values(vehicle)
      effects_block = format_vehicle_effects(shot, vehicle)

      chase_str = if chase_line != "", do: " #{chase_line}\n", else: ""

      "- **#{vehicle.name}**#{location_str} \n #{pursuer_evader} - #{position}\n#{chase_str} #{action_values_line}\n#{effects_block}"
    else
      "- **#{vehicle.name}**#{location_str} \n #{pursuer_evader} - #{position}\n"
    end
  end

  # Check if character is a "good guy" (PC or Ally)
  defp good_guy?(%Character{action_values: avs}) do
    type = Map.get(avs, "Type", "PC")
    type == "PC" || type == "Ally"
  end

  defp good_guy_vehicle?(%Vehicle{action_values: avs}) do
    type = Map.get(avs, "Type", "PC")
    type == "PC" || type == "Ally"
  end

  # Format character action values line
  defp format_character_action_values(%Character{action_values: avs, impairments: impairments}) do
    main_attack = Map.get(avs, "MainAttack", "Guns")
    secondary_attack = Map.get(avs, "SecondaryAttack")
    char_type = Map.get(avs, "Type", "PC")

    [
      format_action_value(avs, main_attack, impairments, true),
      format_action_value(avs, secondary_attack, impairments, true),
      format_action_value(avs, "Defense", impairments, true),
      if(char_type == "PC", do: format_fortune(avs), else: nil),
      format_action_value(avs, "Toughness", 0, false),
      format_action_value(avs, "Speed", 0, false)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # Format vehicle action values line
  defp format_vehicle_action_values(%Vehicle{action_values: avs}) do
    [
      format_action_value(avs, "Acceleration", 0, false),
      format_action_value(avs, "Handling", 0, false),
      format_action_value(avs, "Squeal", 0, false),
      format_action_value(avs, "Frame", 0, false)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # Format a single action value
  defp format_action_value(_avs, nil, _impairments, _apply_impairments), do: nil
  defp format_action_value(_avs, "", _impairments, _apply_impairments), do: nil

  defp format_action_value(avs, key, impairments, apply_impairments) do
    value = Map.get(avs, key)

    cond do
      is_nil(value) ->
        nil

      to_integer(value) <= 0 ->
        nil

      true ->
        base_value = to_integer(value)
        impairment_count = if apply_impairments, do: to_integer(impairments), else: 0
        final_value = base_value - impairment_count
        asterisk = if apply_impairments && impairment_count > 0, do: "*", else: ""
        "#{key} #{final_value}#{asterisk}"
    end
  end

  # Format fortune value (for PCs)
  defp format_fortune(avs) do
    max_fortune = to_integer(Map.get(avs, "Max Fortune", 0))

    if max_fortune > 0 do
      current_fortune = to_integer(Map.get(avs, "Fortune", 0))
      fortune_type = Map.get(avs, "FortuneType", "Fortune")
      "#{fortune_type} #{current_fortune}/#{max_fortune}"
    else
      nil
    end
  end

  # Format wounds and impairments
  defp wounds_and_impairments(%Character{action_values: avs, impairments: impairments}) do
    wounds = to_integer(Map.get(avs, "Wounds", 0))
    imp = to_integer(impairments)

    wounds_str = if wounds > 0, do: "#{wounds} Wounds", else: nil
    imp_str = if imp > 0, do: "(#{imp} #{pluralize("Impairment", imp)})", else: nil

    [wounds_str, imp_str]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # Format chase points and impairments for vehicles
  defp chase_points_and_impairments(%Vehicle{action_values: avs, impairments: impairments}) do
    chase = to_integer(Map.get(avs, "Chase Points", 0))
    condition = to_integer(Map.get(avs, "Condition Points", 0))
    imp = to_integer(impairments)

    chase_str = if chase > 0, do: "#{chase} Chase", else: nil
    condition_str = if condition > 0, do: "#{condition} Condition Points", else: nil
    imp_str = if imp > 0, do: "(#{imp} #{pluralize("Impairment", imp)})", else: nil

    [chase_str, condition_str, imp_str]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # Format character effects for a shot
  defp format_character_effects(%Shot{character_effects: effects}, character)
       when is_list(effects) do
    if Enum.empty?(effects) do
      ""
    else
      effect_lines =
        effects
        |> Enum.map(&format_character_effect(&1, character))
        |> Enum.join("\n ")

      "  ```diff\n #{effect_lines}\n ```\n"
    end
  end

  defp format_character_effects(_, _), do: ""

  # Format vehicle effects for a shot
  defp format_vehicle_effects(%Shot{character_effects: effects}, vehicle)
       when is_list(effects) do
    if Enum.empty?(effects) do
      ""
    else
      effect_lines =
        effects
        |> Enum.map(&format_character_effect(&1, vehicle))
        |> Enum.join("\n ")

      "  ```diff\n #{effect_lines}\n ```\n"
    end
  end

  defp format_vehicle_effects(_, _), do: ""

  # Format a single character effect
  # For characters, resolve "MainAttack" to actual attack type
  defp format_character_effect(%CharacterEffect{} = effect, %Character{action_values: avs}) do
    # If action_value is "MainAttack", look up the character's main attack
    action_value =
      case effect.action_value do
        "MainAttack" -> Map.get(avs, "MainAttack", "")
        other -> other || ""
      end

    format_effect_line(effect, action_value)
  end

  # For vehicles, no MainAttack resolution needed
  defp format_character_effect(%CharacterEffect{} = effect, %Vehicle{}) do
    action_value = effect.action_value || ""
    format_effect_line(effect, action_value)
  end

  # Fallback for nil or other types
  defp format_character_effect(%CharacterEffect{} = effect, _) do
    action_value = effect.action_value || ""
    format_effect_line(effect, action_value)
  end

  # Format the actual effect line
  defp format_effect_line(%CharacterEffect{} = effect, action_value) do
    name = effect.name || ""

    description =
      if effect.description && effect.description != "", do: " (#{effect.description})", else: ""

    status = Map.get(@severities, effect.severity || "info", "")
    change = effect.change || ""

    name = if description != "" || change != "", do: "#{name}:", else: name

    "#{status}#{name}#{description} #{action_value} #{change}"
    |> String.trim()
  end

  # Priority order for event types (lower = more interesting, show first)
  @event_priority %{
    "attack" => 1,
    "chase_action" => 2,
    "escape_attempt" => 3,
    "boost" => 4,
    "up_check" => 5,
    "movement" => 6,
    "act" => 7
  }

  # Get latest fight event description
  # Extracts detailed description from nested event details when available
  # Prioritizes more interesting event types (attacks over acts)
  defp get_latest_event(%Fight{fight_events: events}) when is_list(events) do
    events
    # Sort by time descending, then by priority (so attacks come before acts at same time)
    |> Enum.sort_by(
      fn event ->
        priority = Map.get(@event_priority, event.event_type, 10)
        {event.created_at, priority}
      end,
      fn {time1, pri1}, {time2, pri2} ->
        case DateTime.compare(time1, time2) do
          :gt -> true
          :lt -> false
          :eq -> pri1 <= pri2
        end
      end
    )
    |> List.first()
    |> case do
      nil -> ""
      event -> extract_event_description(event)
    end
  end

  defp get_latest_event(_), do: ""

  # Extract the most descriptive text from a fight event
  # For chase actions, the detailed description is nested in vehicle_updates
  defp extract_event_description(%{details: details, description: fallback_description})
       when is_map(details) do
    # Try to get detailed description from vehicle_updates (chase actions)
    vehicle_description =
      details
      |> Map.get("vehicle_updates", [])
      |> List.first()
      |> case do
        %{"event" => %{"description" => desc}} when is_binary(desc) and desc != "" -> desc
        _ -> nil
      end

    # Try to get detailed description from character_updates (combat actions)
    character_description =
      details
      |> Map.get("character_updates", [])
      |> List.first()
      |> case do
        %{"event" => %{"description" => desc}} when is_binary(desc) and desc != "" -> desc
        _ -> nil
      end

    # Return the first available detailed description, or fall back to top-level
    vehicle_description || character_description || fallback_description || ""
  end

  defp extract_event_description(%{description: description}) do
    description || ""
  end

  defp extract_event_description(_), do: ""

  # Helper to convert value to integer
  defp to_integer(nil), do: 0
  defp to_integer(val) when is_integer(val), do: val

  defp to_integer(val) when is_binary(val) do
    case Integer.parse(val) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp to_integer(_), do: 0

  # Helper to pluralize
  defp pluralize(word, 1), do: word
  defp pluralize(word, _), do: "#{word}s"

  # Get the location name from the shot's location_ref association
  defp get_location_name(shot) do
    case Map.get(shot, :location_ref) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      location -> location.name
    end
  end
end
