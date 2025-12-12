defmodule ShotElixir.Discord.Notifications do
  @moduledoc """
  Helper module for triggering Discord notifications when fight state changes.
  Uses Oban uniqueness to debounce rapid updates (2-second window).
  """
  alias ShotElixir.Workers.DiscordNotificationWorker

  @doc """
  Enqueues a Discord notification job if the fight has Discord info (server_id and channel_id).
  Uses Oban's unique constraint to debounce: only one job per fight within 2 seconds.
  Returns :ok regardless of whether job was enqueued (for easy piping).
  """
  def maybe_notify_discord(%{server_id: nil}), do: :ok
  def maybe_notify_discord(%{channel_id: nil}), do: :ok

  def maybe_notify_discord(%{id: fight_id, server_id: _, channel_id: _}) do
    %{"fight_id" => fight_id}
    |> DiscordNotificationWorker.new(unique: [period: 2, keys: [:fight_id]])
    |> Oban.insert()

    :ok
  end

  def maybe_notify_discord(_), do: :ok
end
