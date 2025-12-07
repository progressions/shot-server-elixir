defmodule ShotElixirWeb.Api.V2.FightEventView do
  @moduledoc """
  View module for rendering fight events as JSON.
  Builds meaningful descriptions from event details.
  """

  def render("index.json", %{fight_events: fight_events}) do
    %{
      fight_events: Enum.map(fight_events, &render_fight_event/1)
    }
  end

  def render("show.json", %{fight_event: fight_event}) do
    render_fight_event(fight_event)
  end

  defp render_fight_event(fight_event) do
    %{
      id: fight_event.id,
      fight_id: fight_event.fight_id,
      event_type: fight_event.event_type,
      description: build_description(fight_event),
      details: fight_event.details || %{},
      created_at: fight_event.created_at
    }
  end

  # Build description from details, falling back to stored description
  defp build_description(%{event_type: "chase_action", details: details}) when is_map(details) do
    case details do
      %{"vehicle_updates" => updates} when is_list(updates) ->
        build_chase_description(updates)

      _ ->
        "Chase action"
    end
  end

  defp build_description(%{event_type: "up_check", details: details}) when is_map(details) do
    character_name = details["character_name"] || "Character"
    success = details["success"]
    swerve = details["swerve"]

    result = if success, do: "passed", else: "failed"
    swerve_text = if swerve, do: " (swerve: #{swerve})", else: ""

    "#{character_name} #{result} Up Check#{swerve_text}"
  end

  defp build_description(%{event_type: "boost", details: details}) when is_map(details) do
    booster_name = details["booster_name"] || "Character"
    target_name = details["target_name"] || "ally"
    boost_type = details["boost_type"] || "attack"

    "#{booster_name} boosted #{target_name}'s #{boost_type}"
  end

  defp build_description(%{event_type: "wound_threshold", details: details})
       when is_map(details) do
    character_name = details["character_name"] || "Character"
    wounds = details["wounds"]

    wounds_text = if wounds, do: " (#{wounds} wounds)", else: ""
    "#{character_name} reached 35 wound threshold#{wounds_text}"
  end

  defp build_description(%{event_type: "out_of_fight", details: details}) when is_map(details) do
    character_name = details["character_name"] || "Character"
    reason = details["reason"]

    reason_text = if reason, do: ": #{reason}", else: ""
    "#{character_name} is out of the fight#{reason_text}"
  end

  defp build_description(%{description: description})
       when is_binary(description) and description != "" do
    description
  end

  defp build_description(%{event_type: event_type}) do
    event_type
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  # Build chase description from vehicle updates
  defp build_chase_description(vehicle_updates) do
    descriptions =
      Enum.map(vehicle_updates, fn update ->
        vehicle_name = update["vehicle_name"] || "Vehicle"
        action_values = update["action_values"] || %{}
        position = update["position"]

        parts = []

        # Chase Points change
        parts =
          case action_values["Chase Points"] do
            nil -> parts
            0 -> parts
            cp when is_number(cp) and cp > 0 -> parts ++ ["gained #{cp} Chase Points"]
            cp when is_number(cp) -> parts ++ ["lost #{abs(cp)} Chase Points"]
            _ -> parts
          end

        # Condition Points change
        parts =
          case action_values["Condition Points"] do
            nil -> parts
            0 -> parts
            cp when is_number(cp) and cp > 0 -> parts ++ ["took #{cp} Condition Points"]
            cp when is_number(cp) -> parts ++ ["repaired #{abs(cp)} Condition Points"]
            _ -> parts
          end

        # Position change
        parts =
          if position do
            parts ++ ["moved to #{position} position"]
          else
            parts
          end

        if Enum.empty?(parts) do
          "#{vehicle_name} performed a chase action"
        else
          "#{vehicle_name} #{Enum.join(parts, ", ")}"
        end
      end)

    case descriptions do
      [] -> "Chase action"
      _ -> Enum.join(descriptions, "; ")
    end
  end
end
