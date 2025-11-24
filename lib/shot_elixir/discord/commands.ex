defmodule ShotElixir.Discord.Commands do
  @moduledoc """
  Handles Discord slash command interactions.
  """
  alias Nostrum.Api
  alias ShotElixir.{Fights, Campaigns}
  alias ShotElixir.Discord.CurrentFight
  alias ShotElixir.Workers.DiscordNotificationWorker
  alias ShotElixir.Services.DiceRoller

  require Logger

  @doc """
  Handles the /start command to start a fight in Discord.
  """
  def handle_start(interaction) do
    channel_id = interaction.channel_id
    server_id = interaction.guild_id
    fight_name = get_option(interaction, "name")

    unless channel_id do
      respond(interaction, "Error: Discord channel ID is missing.", ephemeral: true)
      :ok
    end

    case get_campaign(server_id) do
      nil ->
        respond(interaction, "No campaign found for this server.", ephemeral: true)

      campaign ->
        fight =
          Fights.list_fights(campaign.id)
          |> Enum.find(&(&1.name == fight_name && &1.active))

        case fight do
          nil ->
            respond(interaction, "Couldn't find that fight!")

          fight ->
            # Update fight with Discord info
            {:ok, fight} =
              Fights.update_fight(fight, %{
                server_id: server_id,
                channel_id: channel_id,
                fight_message_id: nil
              })

            # Set as current fight
            CurrentFight.set(server_id, fight.id)

            # Enqueue notification job
            %{fight_id: fight.id}
            |> DiscordNotificationWorker.new()
            |> Oban.insert()

            respond(interaction, "Starting fight: #{fight.name}")
        end
    end
  end

  @doc """
  Handles the /halt command to stop the current fight.
  """
  def handle_halt(interaction) do
    channel_id = interaction.channel_id
    server_id = interaction.guild_id

    unless channel_id do
      respond(interaction, "Error: Discord channel ID is missing.", ephemeral: true)
      :ok
    end

    case CurrentFight.get(server_id) do
      nil ->
        respond(interaction, "There is no current fight.")

      fight_id ->
        case Fights.get_fight(fight_id) do
          nil ->
            respond(interaction, "Fight not found.")

          fight ->
            # Clear Discord fields
            {:ok, _fight} =
              Fights.update_fight(fight, %{
                server_id: nil,
                channel_id: nil,
                fight_message_id: nil
              })

            # Clear current fight
            CurrentFight.set(server_id, nil)

            respond(interaction, "Stopping fight: #{fight.name}")

            # If there's a message to edit, do it in the background
            if fight.fight_message_id && fight.channel_id do
              Task.start(fn ->
                Api.edit_message(
                  fight.channel_id,
                  fight.fight_message_id,
                  content: "Fight stopped: #{fight.name}"
                )
              end)
            end
        end
    end
  end

  @doc """
  Handles the /roll command to roll a single die.
  """
  def handle_roll(interaction) do
    roll = DiceRoller.die_roll()
    respond(interaction, "Rolling dice: #{roll}")
  end

  @doc """
  Handles the /swerve command to roll a swerve (positive and negative exploding dice).
  """
  def handle_swerve(interaction) do
    username = interaction.user.username
    swerve = DiceRoller.swerve()
    DiceRoller.save_swerve(swerve, username)

    messages = [
      "Rolling swerve#{if username, do: " for #{username}", else: ""}",
      DiceRoller.discord_format(swerve, username)
    ]

    respond(interaction, Enum.join(messages, "\n"))
  end

  @doc """
  Handles the /swerves command to show user's swerve history.
  """
  def handle_swerves(interaction) do
    username = interaction.user.username
    swerves = DiceRoller.load_swerves(username)

    messages =
      if Enum.empty?(swerves) do
        ["No swerves found for #{username}"]
      else
        (["Swerves for #{username}"] ++
           Enum.flat_map(swerves, fn swerve ->
             rolled_at =
               if swerve.rolled_at do
                 swerve.rolled_at
                 |> DateTime.from_naive!("Etc/UTC")
                 |> Calendar.strftime("%Y-%m-%d %l:%M %p")
               end

             message = DiceRoller.discord_format(swerve, username)
             [if(rolled_at, do: "Rolled on #{rolled_at}", else: nil), message]
           end))
        |> Enum.reject(&is_nil/1)
      end

    respond(interaction, Enum.join(messages, "\n\n"))
  end

  @doc """
  Handles the /clear_swerves command to clear user's swerve history.
  """
  def handle_clear_swerves(interaction) do
    username = interaction.user.username
    DiceRoller.clear_swerves(username)
    respond(interaction, "Cleared swerves for #{username}")
  end

  # Private helpers

  defp get_option(interaction, name) do
    interaction.data.options
    |> Enum.find(&(&1.name == name))
    |> case do
      nil -> nil
      option -> option.value
    end
  end

  defp get_campaign(_server_id) do
    # In Rails, this uses CurrentCampaign.get(server_id: server_id)
    # For now, we'll get the first active campaign - you may need to implement
    # an Agent-based CurrentCampaign service similar to CurrentFight
    Campaigns.list_campaigns()
    |> Enum.find(& &1.active)
  end

  defp respond(interaction, content, opts \\ []) do
    ephemeral = Keyword.get(opts, :ephemeral, false)

    flags = if ephemeral, do: 64, else: 0

    Api.create_interaction_response(interaction, %{
      type: 4,
      data: %{
        content: content,
        flags: flags
      }
    })
  end
end
