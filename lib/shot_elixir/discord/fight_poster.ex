defmodule ShotElixir.Discord.FightPoster do
  @moduledoc """
  Generates markdown-formatted fight information for Discord.
  Similar to Rails FightPoster service.
  """
  alias ShotElixir.{Fights, Repo}
  alias ShotElixir.Fights.Shot
  alias ShotElixir.Characters.Character
  alias ShotElixir.Vehicles.Vehicle

  @doc """
  Generates markdown representation of a fight for Discord display.
  """
  def shots(fight_id) when is_binary(fight_id) do
    fight =
      Fights.get_fight!(fight_id)
      |> Repo.preload([:shots, shots: [:character, :vehicle]])

    generate_markdown(fight)
  end

  defp generate_markdown(fight) do
    """
    # #{fight.name}
    #{if fight.description, do: clean_description(fight.description), else: ""}
    ## Sequence #{fight.sequence}

    #{active_effects_section(fight)}
    #{shot_order_section(fight)}

    #{latest_event(fight)}
    """
  end

  defp clean_description(description) do
    # Basic HTML to markdown cleaning
    # In production, you might want to use a proper HTML->Markdown converter
    description
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
  end

  defp active_effects_section(_fight) do
    # TODO: Implement active effects display
    # This would require loading fight effects and filtering by sequence/shot
    ""
  end

  defp shot_order_section(fight) do
    fight.shots
    |> Enum.group_by(& &1.shot)
    |> Enum.sort_by(fn {shot, _} -> -(shot || 1000) end)
    |> Enum.map(fn {shot, characters} ->
      """
      ## Shot #{shot || "Unassigned"}
      #{Enum.map(characters, &format_shot_character/1) |> Enum.join("\n")}
      """
    end)
    |> Enum.join("\n")
  end

  defp format_shot_character(%Shot{character: %Character{} = char}) when not is_nil(char) do
    """
    **#{char.name}** #{if char.player_name, do: "(#{char.player_name})", else: ""}
    #{action_values_line(char)}
    #{wounds_line(char)}
    """
  end

  defp format_shot_character(%Shot{vehicle: %Vehicle{} = vehicle}) when not is_nil(vehicle) do
    """
    **#{vehicle.name}** (Vehicle)
    #{vehicle_stats_line(vehicle)}
    """
  end

  defp format_shot_character(_), do: ""

  defp action_values_line(char) do
    # Format key action values
    avs = char.action_values || %{}

    [
      format_av(avs, "Defense"),
      format_av(avs, "Toughness"),
      format_av(avs, "Speed")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp format_av(avs, key) do
    case Map.get(avs, key) do
      nil -> nil
      0 -> nil
      value -> "#{key}: #{value}"
    end
  end

  defp wounds_line(char) do
    avs = char.action_values || %{}
    wounds = Map.get(avs, "Wounds", 0)
    impairments = char.impairments || 0

    cond do
      wounds > 0 && impairments > 0 ->
        "Wounds: #{wounds} (#{impairments} Impairments)"

      wounds > 0 ->
        "Wounds: #{wounds}"

      true ->
        ""
    end
  end

  defp vehicle_stats_line(vehicle) do
    avs = vehicle.action_values || %{}

    [
      format_av(avs, "Handling"),
      format_av(avs, "Squeal"),
      format_av(avs, "Frame")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" | ")
  end

  defp latest_event(_fight) do
    # TODO: Load and display the latest fight event
    ""
  end
end
