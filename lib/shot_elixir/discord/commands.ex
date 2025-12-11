defmodule ShotElixir.Discord.Commands do
  @moduledoc """
  Handles Discord slash command interactions.
  """
  alias Nostrum.Api
  alias Nostrum.Api.Message
  alias ShotElixir.{Fights, Campaigns, Characters, Parties, Accounts}
  alias ShotElixir.Discord.{CurrentFight, CurrentCampaign, LinkCodes}
  alias ShotElixir.Workers.DiscordNotificationWorker
  alias ShotElixir.Services.DiceRoller

  require Logger

  @doc """
  Handles autocomplete for the /start command's name parameter.
  """
  def handle_autocomplete(interaction) do
    server_id = interaction.guild_id

    # Get the user's current input for the fight name
    focused_option =
      interaction.data.options
      |> Enum.find(&Map.get(&1, :focused, false))

    input_value = if focused_option, do: focused_option.value || "", else: ""

    # Get campaign for this server
    campaign = get_campaign(server_id)

    choices =
      if campaign do
        # Get active fights for this campaign
        Fights.list_fights(campaign.id)
        |> Enum.filter(& &1.active)
        |> Enum.filter(&String.contains?(String.downcase(&1.name), String.downcase(input_value)))
        # Discord allows max 25 choices
        |> Enum.take(25)
        |> Enum.map(&%{name: &1.name, value: &1.name})
      else
        []
      end

    # Respond with autocomplete choices
    Api.create_interaction_response(interaction, %{
      type: 8,
      # APPLICATION_COMMAND_AUTOCOMPLETE_RESULT
      data: %{
        choices: choices
      }
    })
  end

  @doc """
  Handles the /start command to start a fight in Discord.
  """
  def handle_start(interaction) do
    channel_id = interaction.channel_id
    server_id = interaction.guild_id
    fight_name = get_option(interaction, "name")

    cond do
      is_nil(channel_id) ->
        respond(interaction, "Error: Discord channel ID is missing.", ephemeral: true)

      true ->
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
                case Fights.update_fight(fight, %{
                       server_id: to_string(server_id),
                       channel_id: to_string(channel_id),
                       fight_message_id: nil
                     }) do
                  {:ok, fight} ->
                    # Set as current fight
                    CurrentFight.set(server_id, fight.id)

                    # Enqueue notification job
                    case %{fight_id: fight.id}
                         |> DiscordNotificationWorker.new()
                         |> Oban.insert() do
                      {:ok, _job} ->
                        respond(interaction, "Starting fight: #{fight.name}")

                      {:error, reason} ->
                        Logger.error(
                          "DISCORD: Failed to enqueue notification job: #{inspect(reason)}"
                        )

                        respond(interaction, "Failed to start fight notification")
                    end

                  {:error, changeset} ->
                    Logger.error("DISCORD: Failed to update fight: #{inspect(changeset)}")
                    respond(interaction, "Failed to update fight")
                end
            end
        end
    end
  end

  @doc """
  Handles the /halt command to stop the current fight.
  """
  def handle_halt(interaction) do
    channel_id = interaction.channel_id
    server_id = interaction.guild_id

    cond do
      is_nil(channel_id) ->
        respond(interaction, "Error: Discord channel ID is missing.", ephemeral: true)

      true ->
        case CurrentFight.get(server_id) do
          nil ->
            respond(interaction, "There is no current fight.")

          fight_id ->
            case Fights.get_fight(fight_id) do
              nil ->
                respond(interaction, "Fight not found.")

              fight ->
                # Clear Discord fields
                case Fights.update_fight(fight, %{
                       server_id: nil,
                       channel_id: nil,
                       fight_message_id: nil
                     }) do
                  {:ok, _fight} ->
                    # Clear current fight
                    CurrentFight.set(server_id, nil)

                    respond(interaction, "Stopping fight: #{fight.name}")

                    # If there's a message to edit, do it in the background
                    if fight.fight_message_id && fight.channel_id do
                      Task.start(fn ->
                        Message.edit(
                          fight.channel_id,
                          fight.fight_message_id,
                          content: "Fight stopped: #{fight.name}"
                        )
                      end)
                    end

                  {:error, changeset} ->
                    Logger.error("DISCORD: Failed to update fight: #{inspect(changeset)}")
                    respond(interaction, "Failed to stop fight")
                end
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
                 # rolled_at is already a DateTime, no need to convert
                 Calendar.strftime(swerve.rolled_at, "%Y-%m-%d %l:%M %p")
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

  @doc """
  Handles the /list command to list available fights.
  """
  def handle_list(interaction) do
    server_id = interaction.guild_id

    if is_nil(server_id) do
      respond(interaction, "This command can only be used in a server.", ephemeral: true)
    else
      case get_campaign(server_id) do
        nil ->
          respond(interaction, "No campaign found for this server.", ephemeral: true)

        campaign ->
          fights =
            Fights.list_fights(campaign.id)
            |> Enum.filter(& &1.active)

          if Enum.empty?(fights) do
            respond(interaction, "No active fights in #{campaign.name}.")
          else
            fight_list =
              fights
              |> Enum.map(fn fight -> "• #{fight.name}" end)
              |> Enum.join("\n")

            respond(interaction, "**Active fights in #{campaign.name}:**\n#{fight_list}")
          end
      end
    end
  end

  @doc """
  Handles the /campaigns command to list all campaigns.
  """
  def handle_campaigns(interaction) do
    server_id = interaction.guild_id

    if is_nil(server_id) do
      respond(interaction, "This command can only be used in a server.", ephemeral: true)
    else
      campaigns = Campaigns.list_campaigns()

      if Enum.empty?(campaigns) do
        respond(interaction, "No campaigns available.")
      else
        current_campaign = get_campaign(server_id)

        campaign_list =
          campaigns
          |> Enum.map(fn campaign ->
            marker = if current_campaign && current_campaign.id == campaign.id, do: " ✓", else: ""
            "• #{campaign.name}#{marker}"
          end)
          |> Enum.join("\n")

        respond(
          interaction,
          "**Available campaigns:**\n#{campaign_list}\n\nUse `/campaign <name>` to set the active campaign."
        )
      end
    end
  end

  @doc """
  Handles the /campaign command to set the current campaign for a server.
  """
  def handle_campaign(interaction) do
    server_id = interaction.guild_id
    campaign_name = get_option(interaction, "name")

    cond do
      is_nil(server_id) ->
        respond(interaction, "This command can only be used in a server.", ephemeral: true)

      is_nil(campaign_name) || campaign_name == "" ->
        respond(interaction, "Please provide a campaign name.", ephemeral: true)

      true ->
        campaigns = Campaigns.list_campaigns()

        campaign =
          Enum.find(campaigns, &(String.downcase(&1.name) == String.downcase(campaign_name)))

        case campaign do
          nil ->
            respond(interaction, "Couldn't find campaign \"#{campaign_name}\".", ephemeral: true)

          campaign ->
            CurrentCampaign.set(server_id, campaign.id)
            respond(interaction, "Current campaign set to **#{campaign.name}**.")
        end
    end
  end

  @doc """
  Handles autocomplete for the /campaign command's name parameter.
  """
  def handle_campaign_autocomplete(interaction) do
    # Get the user's current input for the campaign name
    focused_option =
      interaction.data.options
      |> Enum.find(&Map.get(&1, :focused, false))

    input_value = if focused_option, do: focused_option.value || "", else: ""

    choices =
      Campaigns.list_campaigns()
      |> Enum.filter(&String.contains?(String.downcase(&1.name), String.downcase(input_value)))
      # Discord allows max 25 choices
      |> Enum.take(25)
      |> Enum.map(&%{name: &1.name, value: &1.name})

    # Respond with autocomplete choices
    Api.create_interaction_response(interaction, %{
      type: 8,
      # APPLICATION_COMMAND_AUTOCOMPLETE_RESULT
      data: %{
        choices: choices
      }
    })
  end

  @default_party_name "The Dragons"

  @doc """
  Handles the /advance_party command to add an advancement to all characters in a party.
  """
  def handle_advance_party(interaction) do
    server_id = interaction.guild_id
    party_name = get_option(interaction, "party") || @default_party_name
    description = get_option(interaction, "description")

    if is_nil(server_id) do
      respond(interaction, "This command can only be used in a server.", ephemeral: true)
    else
      case get_campaign(server_id) do
        nil ->
          respond(interaction, "No campaign found for this server.", ephemeral: true)

        campaign ->
          # Find the party by name in the current campaign
          parties = Parties.list_parties(campaign.id)

          party =
            Enum.find(parties, fn p ->
              String.downcase(p.name) == String.downcase(party_name)
            end)

          case party do
            nil ->
              respond(interaction, "Couldn't find party \"#{party_name}\" in #{campaign.name}.",
                ephemeral: true
              )

            party ->
              # Get all active characters from the party (exclude vehicles and inactive)
              characters =
                party.memberships
                |> Enum.filter(& &1.character_id)
                |> Enum.map(& &1.character)
                |> Enum.reject(&is_nil/1)
                |> Enum.filter(& &1.active)

              if Enum.empty?(characters) do
                respond(interaction, "No characters found in party \"#{party.name}\".",
                  ephemeral: true
                )
              else
                # Create an advancement for each character
                results =
                  Enum.map(characters, fn character ->
                    attrs = if description, do: %{description: description}, else: %{}
                    {character, Characters.create_advancement(character.id, attrs)}
                  end)

                # Check for any errors
                {successes, failures} =
                  Enum.split_with(results, fn {_char, result} ->
                    match?({:ok, _}, result)
                  end)

                success_names =
                  successes
                  |> Enum.map(fn {char, _} -> char.name end)
                  |> Enum.join(", ")

                cond do
                  Enum.empty?(failures) ->
                    respond(interaction, "Added advancement to #{success_names}")

                  Enum.empty?(successes) ->
                    respond(interaction, "Failed to add advancement to all characters.")

                  true ->
                    failure_count = length(failures)

                    respond(
                      interaction,
                      "Added advancement to #{success_names}. Failed for #{failure_count} character(s)."
                    )
                end
              end
          end
      end
    end
  end

  @doc """
  Handles autocomplete for the /advance_party command's party parameter.
  """
  def handle_advance_party_autocomplete(interaction) do
    server_id = interaction.guild_id

    # Get the user's current input for the party name
    focused_option =
      interaction.data.options
      |> Enum.find(&Map.get(&1, :focused, false))

    input_value = if focused_option, do: focused_option.value || "", else: ""

    choices =
      case get_campaign(server_id) do
        nil ->
          []

        campaign ->
          Parties.list_parties(campaign.id)
          |> Enum.filter(
            &String.contains?(String.downcase(&1.name), String.downcase(input_value))
          )
          # Discord allows max 25 choices
          |> Enum.take(25)
          |> Enum.map(&%{name: &1.name, value: &1.name})
      end

    # Respond with autocomplete choices
    Api.create_interaction_response(interaction, %{
      type: 8,
      # APPLICATION_COMMAND_AUTOCOMPLETE_RESULT
      data: %{
        choices: choices
      }
    })
  end

  @doc """
  Handles the /link command to generate a code for linking Discord to Chi War.
  """
  def handle_link(interaction) do
    discord_id = interaction.user.id
    discord_username = interaction.user.username

    # Check if this Discord user is already linked
    case Accounts.get_user_by_discord_id(discord_id) do
      nil ->
        # Generate a link code
        code = LinkCodes.generate(discord_id, discord_username)
        link_url = "https://chiwar.net/link-discord?code=#{code}"

        respond(
          interaction,
          """
          **Link your Discord account to Chi War**

          **Option 1:** Click this link (requires login):
          #{link_url}

          **Option 2:** Enter code manually at https://chiwar.net/profile
          Code: **#{code}**

          Code expires in 5 minutes.
          """,
          ephemeral: true
        )

      user ->
        respond(
          interaction,
          "Your Discord account is already linked to Chi War user **#{user.name}** (#{user.email}).\n\nTo unlink, use the Chi War website.",
          ephemeral: true
        )
    end
  end

  @doc """
  Handles the /whoami command to show details about the user's linked Chi War account.
  """
  def handle_whoami(interaction) do
    discord_id = interaction.user.id
    message = build_whoami_response(discord_id)
    respond(interaction, message, ephemeral: true)
  end

  @doc """
  Handles the /stats command to show the user's character stats during a fight.
  """
  def handle_stats(interaction) do
    discord_id = interaction.user.id
    server_id = interaction.guild_id
    message = build_stats_response(discord_id, server_id)
    respond(interaction, message, ephemeral: true)
  end

  @doc """
  Builds the response message for the /stats command.
  Returns a string with the user's character stats in the current fight.
  """
  def build_stats_response(discord_id, server_id) do
    case Accounts.get_user_by_discord_id(discord_id) do
      nil ->
        """
        Your Discord account is not linked to Chi War.
        Use `/link` to generate a link code.
        """

      user ->
        build_stats_for_user(user, server_id)
    end
  end

  defp build_stats_for_user(user, server_id) do
    # Get the current fight for this server
    case CurrentFight.get(server_id) do
      nil ->
        "There is no active fight in this server. Use `/start` to begin a fight."

      fight_id ->
        build_stats_for_fight(user, fight_id)
    end
  end

  defp build_stats_for_fight(user, fight_id) do
    # Get the fight with shots preloaded
    case Fights.get_fight_with_shots(fight_id) do
      nil ->
        "Fight not found."

      fight ->
        # Find the user's character shots in this fight
        user_shots = find_user_character_shots(fight, user)

        if Enum.empty?(user_shots) do
          "You don't have any characters in the fight \"#{fight.name}\"."
        else
          format_character_stats(fight, user_shots)
        end
    end
  end

  defp find_user_character_shots(fight, user) do
    fight.shots
    |> Enum.filter(fn shot ->
      shot.character && shot.character.user_id == user.id
    end)
  end

  defp format_character_stats(fight, shots) do
    header = "**Your Characters in #{fight.name}**\n"

    character_sections =
      shots
      |> Enum.map(&format_single_character_stats/1)
      |> Enum.join("\n\n")

    header <> character_sections
  end

  defp format_single_character_stats(shot) do
    character = shot.character
    av = character.action_values || %{}

    # Get key combat stats
    wounds = av["Wounds"] || 0
    defense = av["Defense"] || 0
    toughness = av["Toughness"] || 0
    speed = av["Speed"] || 0
    fortune = av["Fortune"] || 0
    max_fortune = av["Max Fortune"] || 0
    impairments = shot.impairments || character.impairments || 0

    # Get attack values
    main_attack = av["MainAttack"] || "Guns"
    main_attack_value = av[main_attack] || 0
    secondary_attack = av["SecondaryAttack"]

    secondary_attack_line =
      if secondary_attack && secondary_attack != "" do
        secondary_value = av[secondary_attack] || 0
        "#{secondary_attack}: **#{secondary_value}**"
      else
        nil
      end

    # Get shot position
    shot_position = shot.shot

    shot_line =
      if shot_position do
        "Shot: **#{shot_position}**"
      else
        "Shot: _Not set_"
      end

    # Get active effects (handle unloaded association)
    effects =
      case shot.character_effects do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        loaded -> loaded
      end

    effects_line =
      if Enum.empty?(effects) do
        nil
      else
        effect_names = Enum.map(effects, & &1.name) |> Enum.join(", ")
        "Effects: #{effect_names}"
      end

    # Build the character section
    lines =
      [
        "**#{character.name}** (#{av["Type"] || "PC"})",
        shot_line,
        "Wounds: **#{wounds}** | Defense: **#{defense}** | Toughness: **#{toughness}**",
        "#{main_attack}: **#{main_attack_value}**",
        secondary_attack_line,
        "Speed: **#{speed}** | Fortune: **#{fortune}/#{max_fortune}**",
        if(impairments > 0, do: "⚠️ Impairments: **#{impairments}**", else: nil),
        effects_line
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(lines, "\n")
  end

  @doc """
  Builds the response message for the /whoami command.
  Returns a string with either the user's profile info or a prompt to link.
  """
  def build_whoami_response(discord_id) do
    case Accounts.get_user_by_discord_id(discord_id) do
      nil ->
        """
        Your Discord account is not linked to Chi War.
        Use `/link` to generate a link code.
        """

      user ->
        # Load the current campaign and characters
        user = ShotElixir.Repo.preload(user, [:current_campaign, :characters])

        role = if user.gamemaster, do: "Gamemaster", else: "Player"

        campaign_line =
          if user.current_campaign do
            "Current Campaign: #{user.current_campaign.name}"
          else
            "Current Campaign: None"
          end

        # Get active PC characters in the current campaign
        characters =
          if user.current_campaign do
            user.characters
            |> Enum.filter(fn char ->
              char.active &&
                char.campaign_id == user.current_campaign_id &&
                Map.get(char.action_values, "Type") == "PC"
            end)
            |> Enum.sort_by(& &1.name)
          else
            []
          end

        characters_section =
          if Enum.empty?(characters) do
            "Characters: None"
          else
            character_list =
              characters
              |> Enum.map(&"• #{&1.name}")
              |> Enum.join("\n")

            "Characters:\n#{character_list}"
          end

        """
        **Your Chi War Profile**
        Name: #{user.name}
        Email: #{user.email}
        Role: #{role}
        #{campaign_line}

        #{characters_section}
        """
    end
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

  defp get_campaign(server_id) do
    # Use the CurrentCampaign agent to get the campaign for this server
    # Falls back to the first active campaign if none is set
    case CurrentCampaign.get(server_id) do
      nil ->
        # Fallback: get the first active campaign
        Campaigns.list_campaigns()
        |> Enum.find(& &1.active)

      campaign ->
        campaign
    end
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
