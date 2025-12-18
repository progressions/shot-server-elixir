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
          "list" -> Commands.handle_list(interaction)
          "campaigns" -> Commands.handle_campaigns(interaction)
          "campaign" -> Commands.handle_campaign(interaction)
          "roll" -> Commands.handle_roll(interaction)
          "swerve" -> Commands.handle_swerve(interaction)
          "swerves" -> Commands.handle_swerves(interaction)
          "clear_swerves" -> Commands.handle_clear_swerves(interaction)
          "advance_party" -> Commands.handle_advance_party(interaction)
          "link" -> Commands.handle_link(interaction)
          "whoami" -> Commands.handle_whoami(interaction)
          "stats" -> Commands.handle_stats(interaction)
          "fortune" -> Commands.handle_fortune(interaction)
          _ -> :noop
        end

      # Application Command Autocomplete
      4 ->
        case interaction.data.name do
          "start" -> Commands.handle_autocomplete(interaction)
          "campaign" -> Commands.handle_campaign_autocomplete(interaction)
          "advance_party" -> Commands.handle_advance_party_autocomplete(interaction)
          "link" -> Commands.handle_link_autocomplete(interaction)
          "fortune" -> Commands.handle_fortune_autocomplete(interaction)
          _ -> :noop
        end

      _ ->
        :noop
    end

    :ok
  end

  def handle_event({:READY, %{user: user} = ready_data, _ws_state}) do
    Logger.info("DISCORD: Bot logged in as #{user.username}##{user.discriminator}")

    # Print the invite URL so it's easy to add the bot to a server
    # Permissions: Send Messages (2048), Embed Links (16384), Read Message History (65536)
    with %{application: %{id: app_id}} <- ready_data do
      permissions = 2048 + 16384 + 65536

      invite_url =
        "https://discord.com/api/oauth2/authorize?client_id=#{app_id}&permissions=#{permissions}&scope=bot%20applications.commands"

      Logger.info("DISCORD: Invite URL: #{invite_url}")
    end

    :ok
  end

  def handle_event(_event) do
    :noop
  end
end
