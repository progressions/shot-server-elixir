defmodule ShotElixir.Discord.Consumer do
  @moduledoc """
  Discord bot consumer that handles slash commands and events.
  """
  use Nostrum.Consumer

  alias Nostrum.Api
  alias ShotElixir.Fights
  alias ShotElixir.Discord.Commands
  alias ShotElixir.Discord.FightPoster
  alias ShotElixir.Workers.DiscordNotificationWorker

  require Logger

  @doc """
  Handles interaction create events (slash commands).
  """
  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    case interaction.data.name do
      "start" -> Commands.handle_start(interaction)
      "halt" -> Commands.handle_halt(interaction)
      "roll" -> Commands.handle_roll(interaction)
      "swerve" -> Commands.handle_swerve(interaction)
      "swerves" -> Commands.handle_swerves(interaction)
      "clear_swerves" -> Commands.handle_clear_swerves(interaction)
      _ -> :noop
    end
  end

  @doc """
  Handle READY event to log bot start.
  """
  def handle_event({:READY, %{user: user}, _ws_state}) do
    Logger.info("DISCORD: Bot logged in as #{user.username}##{user.discriminator}")
    :ok
  end

  @doc """
  Catch-all for other events.
  """
  def handle_event(_event) do
    :noop
  end
end
