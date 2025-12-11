defmodule Mix.Tasks.Discord.RegisterCommands do
  @moduledoc """
  Registers Discord slash commands with the Discord API.

  Usage:
      mix discord.register_commands

  This task should be run after deploying or when Discord commands change.
  """
  use Mix.Task

  alias Nostrum.Api.ApplicationCommand

  @shortdoc "Register Discord slash commands"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Waiting for Discord connection...")
    # Give Nostrum time to connect and populate the cache
    Process.sleep(5000)

    # Get the application ID from the connected bot
    me = Nostrum.Cache.Me.get()

    if is_nil(me) do
      IO.puts("Error: Could not get bot info. Make sure DISCORD_TOKEN is set correctly.")
      System.halt(1)
    end

    app_id = me.id
    IO.puts("Registering Discord slash commands for application #{app_id}...")

    commands = [
      %{
        name: "start",
        description: "Start a fight",
        options: [
          %{
            type: 3,
            # STRING type
            name: "name",
            description: "Fight name",
            required: true,
            autocomplete: true
          }
        ]
      },
      %{
        name: "halt",
        description: "Stop the current fight"
      },
      %{
        name: "list",
        description: "List available fights"
      },
      %{
        name: "campaigns",
        description: "List all campaigns"
      },
      %{
        name: "campaign",
        description: "Set the current campaign for this server",
        options: [
          %{
            type: 3,
            # STRING type
            name: "name",
            description: "Campaign name",
            required: true,
            autocomplete: true
          }
        ]
      },
      %{
        name: "roll",
        description: "Roll a die"
      },
      %{
        name: "swerve",
        description: "Roll a swerve (positive and negative exploding dice)"
      },
      %{
        name: "swerves",
        description: "Show your swerve history"
      },
      %{
        name: "clear_swerves",
        description: "Clear your swerve history"
      },
      %{
        name: "advance_party",
        description: "Add an advancement to all characters in a party",
        options: [
          %{
            type: 3,
            # STRING type
            name: "party",
            description: "Party name (defaults to 'The Dragons')",
            required: false,
            autocomplete: true
          },
          %{
            type: 3,
            # STRING type
            name: "description",
            description: "Advancement description (optional)",
            required: false
          }
        ]
      },
      %{
        name: "link",
        description: "Generate a code to link your Discord account to Chi War"
      },
      %{
        name: "whoami",
        description: "Show details about your linked Chi War account"
      }
    ]

    case ApplicationCommand.bulk_overwrite_global_commands(app_id, commands) do
      {:ok, registered_commands} ->
        IO.puts("Successfully registered #{length(registered_commands)} commands:")

        Enum.each(registered_commands, fn cmd ->
          IO.puts("  - /#{cmd.name}: #{cmd.description}")
        end)

      {:error, error} ->
        IO.puts("Error registering commands: #{inspect(error)}")
        System.halt(1)
    end
  end
end
