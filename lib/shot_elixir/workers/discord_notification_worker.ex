defmodule ShotElixir.Workers.DiscordNotificationWorker do
  @moduledoc """
  Oban worker that sends/updates fight messages in Discord.
  Similar to Rails DiscordNotificationJob.
  """
  use Oban.Worker, queue: :discord, max_attempts: 3

  alias Nostrum.Api.Message
  alias ShotElixir.Fights
  alias ShotElixir.Discord.FightPoster

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"fight_id" => fight_id}}) do
    fight = Fights.get_fight!(fight_id)

    # Check if fight has Discord info
    unless fight.server_id && fight.channel_id do
      Logger.info("DISCORD: Fight #{fight_id} has no Discord info, skipping notification")
      {:ok, :skipped}
    else
      # Generate fight content
      content = FightPoster.shots(fight_id)
      {message_content, embed} = build_message_params(content)

      # Try to edit existing message or send new one
      result =
        if fight.fight_message_id do
          case Message.edit(fight.channel_id, fight.fight_message_id,
                 content: message_content,
                 embeds: [embed]
               ) do
            {:ok, _message} ->
              Logger.info(
                "DISCORD: Updated message #{fight.fight_message_id} for fight #{fight_id}"
              )

              :ok

            {:error, %{status_code: 404}} ->
              # Message not found, send new one
              send_new_message(fight, message_content, embed)

            {:error, reason} ->
              Logger.error("DISCORD: Failed to edit message: #{inspect(reason)}")
              send_new_message(fight, message_content, embed)
          end
        else
          send_new_message(fight, message_content, embed)
        end

      result
    end
  end

  defp send_new_message(fight, message_content, embed) do
    case Message.create(fight.channel_id, content: message_content, embeds: [embed]) do
      {:ok, message} ->
        # Update fight with new message ID
        Fights.update_fight(fight, %{fight_message_id: to_string(message.id)})
        Logger.info("DISCORD: Sent new message #{message.id} for fight #{fight.id}")
        :ok

      {:error, reason} ->
        Logger.error("DISCORD: Failed to send message: #{inspect(reason)}")
        # Clear fight_message_id on failure
        Fights.update_fight(fight, %{fight_message_id: nil})
        {:error, reason}
    end
  end

  defp build_message_params(raw_content) do
    embed = %{
      title: "Fight Update",
      color: 3_447_003,
      # Blue
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    embed =
      if String.length(raw_content) <= 4096 do
        Map.put(embed, :description, raw_content)
      else
        # Split into description and fields for long content
        description = String.slice(raw_content, 0..4095)
        remaining = String.slice(raw_content, 4096..-1//1)

        fields = build_fields(remaining, [])

        embed
        |> Map.put(:description, description)
        |> Map.put(:fields, fields)
      end

    {"", embed}
  end

  defp build_fields("", acc), do: Enum.reverse(acc)

  defp build_fields(_remaining, acc) when length(acc) >= 25 do
    # Discord limit: 25 fields per embed
    truncated_field = %{
      name: "Truncated",
      value: "... (content too long for embed limits)",
      inline: false
    }

    Enum.reverse([truncated_field | acc])
  end

  defp build_fields(remaining, acc) do
    chunk_size = min(1024, String.length(remaining))
    chunk = String.slice(remaining, 0..(chunk_size - 1))
    rest = String.slice(remaining, chunk_size..-1//1)

    field = %{
      name: "Part #{length(acc) + 1}",
      value: chunk,
      inline: false
    }

    build_fields(rest, [field | acc])
  end
end
