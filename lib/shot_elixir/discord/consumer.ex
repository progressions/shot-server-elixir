defmodule ShotElixir.Discord.Consumer do
  @moduledoc """
  Discord bot consumer that handles slash commands and events.
  """
  use Nostrum.Consumer

  alias ShotElixir.Discord.Commands

  require Logger

  @doc """
  Handles Discord events (interactions, ready, etc.).
  """
  def handle_event({:INTERACTION_CREATE, interaction, _ws_state}) do
    case interaction.type do
      # Application Command (slash command execution)
      2 ->
        case interaction.data.name do
          "start" -> Commands.handle_start(interaction)
          "halt" -> Commands.handle_halt(interaction)
          "roll" -> Commands.handle_roll(interaction)
          "swerve" -> Commands.handle_swerve(interaction)
          "swerves" -> Commands.handle_swerves(interaction)
          "clear_swerves" -> Commands.handle_clear_swerves(interaction)
          _ -> :noop
        end

      # Application Command Autocomplete
      4 ->
        case interaction.data.name do
          "start" -> Commands.handle_autocomplete(interaction)
          _ -> :noop
        end

      _ ->
        :noop
    end

    :ok
  end

  def handle_event({:READY, %{user: user}, _ws_state}) do
    Logger.info("DISCORD: Bot logged in as #{user.username}##{user.discriminator}")
    :ok
  end

  def handle_event(_event) do
    :noop
  end
end
