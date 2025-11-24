defmodule Mix.Tasks.Discord.RegisterCommands do
  @moduledoc """
  Registers Discord slash commands with the Discord API.

  Usage:
      mix discord.register_commands

  This task should be run after deploying or when Discord commands change.
  """
  use Mix.Task

  alias Nostrum.Api

  @shortdoc "Register Discord slash commands"

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    IO.puts("Registering Discord slash commands...")

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
      }
    ]

    case Api.bulk_overwrite_global_application_commands(commands) do
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
