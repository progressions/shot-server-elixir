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
        build_fight_autocomplete_choices(campaign.id, input_value)
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
  Builds autocomplete choices for fight selection.
  Returns only active, unended fights matching the input filter.
  """
  def build_fight_autocomplete_choices(campaign_id, input_value \\ "") do
    Fights.list_fights(campaign_id)
    |> Enum.filter(fn fight -> fight.active && is_nil(fight.ended_at) end)
    |> Enum.filter(&String.contains?(String.downcase(&1.name), String.downcase(input_value)))
    # Discord allows max 25 choices
    |> Enum.take(25)
    |> Enum.map(&%{name: &1.name, value: &1.name})
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
                # Update fight with Discord info and set started_at if not already set
                attrs = %{
                  server_id: to_string(server_id),
                  channel_id: to_string(channel_id),
                  fight_message_id: nil
                }

                # Only set started_at if the fight hasn't been started yet
                attrs =
                  if is_nil(fight.started_at) do
                    Map.put(attrs, :started_at, DateTime.utc_now())
                  else
                    attrs
                  end

                case Fights.update_fight(fight, attrs) do
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
            |> Enum.filter(fn fight -> fight.active && is_nil(fight.ended_at) end)

          if Enum.empty?(fights) do
            respond(interaction, "No active fights in #{campaign.name}.", ephemeral: true)
          else
            fight_list =
              fights
              |> Enum.map(fn fight -> "• #{fight.name}" end)
              |> Enum.join("\n")

            respond(interaction, "**Active fights in #{campaign.name}:**\n#{fight_list}",
              ephemeral: true
            )
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
  Handles the /link command to generate a code for linking Discord to Chi War,
  or to set/view the current character when already linked.
  """
  def handle_link(interaction) do
    discord_id = interaction.user.id
    discord_username = interaction.user.username
    character_name = get_option(interaction, "character")

    # Check if this Discord user is already linked
    case Accounts.get_user_with_current_character(discord_id) do
      nil ->
        # Not linked - generate a link code
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
        # Already linked - handle character selection or show status
        if character_name do
          set_current_character(interaction, user, character_name)
        else
          show_link_status(interaction, user)
        end
    end
  end

  defp set_current_character(interaction, user, character_name) do
    # Find the character by name from user's characters in current campaign
    characters = get_user_characters_for_campaign(user)

    character =
      Enum.find(characters, fn char ->
        String.downcase(char.name) == String.downcase(character_name)
      end)

    case character do
      nil ->
        error_msg =
          if user.current_campaign do
            "Couldn't find character \"#{character_name}\" in your current campaign."
          else
            "Couldn't find character \"#{character_name}\"."
          end

        respond(
          interaction,
          error_msg,
          ephemeral: true
        )

      character ->
        case Accounts.set_current_character(user, character.id) do
          {:ok, _user} ->
            # Show the character stats
            message = build_character_stats_message(character)

            respond(
              interaction,
              """
              **Current character set to #{character.name}**

              #{message}
              """,
              ephemeral: true
            )

          {:error, _} ->
            respond(interaction, "Failed to set current character.", ephemeral: true)
        end
    end
  end

  defp show_link_status(interaction, user) do
    campaign_line =
      if user.current_campaign do
        "Campaign: **#{user.current_campaign.name}**"
      else
        "Campaign: _None set_"
      end

    character_section =
      if user.current_character do
        char = user.current_character
        stats_message = build_character_stats_message(char)

        """
        **Current Character: #{char.name}**

        #{stats_message}
        """
      else
        "Current Character: _None set_\n\nUse `/link character:<name>` to select your character."
      end

    respond(
      interaction,
      """
      **Chi War Account: #{user.name}**
      #{campaign_line}

      #{character_section}
      """,
      ephemeral: true
    )
  end

  defp build_character_stats_message(character) do
    av = character.action_values || %{}

    wounds = av["Wounds"] || 0
    defense = av["Defense"] || 0
    toughness = av["Toughness"] || 0
    speed = av["Speed"] || 0
    fortune = av["Fortune"] || 0
    max_fortune = av["Max Fortune"] || 0
    fortune_type = av["FortuneType"] || "Fortune"
    impairments = character.impairments || 0

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

    lines =
      [
        "Type: **#{av["Type"] || "PC"}**",
        "Wounds: **#{wounds}** | Defense: **#{defense}** | Toughness: **#{toughness}**",
        "#{main_attack}: **#{main_attack_value}**",
        secondary_attack_line,
        "Speed: **#{speed}** | #{fortune_type}: **#{fortune}/#{max_fortune}**",
        if(impairments > 0, do: "Impairments: **#{impairments}**", else: nil)
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(lines, "\n")
  end

  defp get_user_characters_for_campaign(user) do
    if user.current_campaign do
      user.characters
      |> Enum.filter(fn char ->
        char.active && char.campaign_id == user.current_campaign_id && !char.is_template
      end)
      |> Enum.sort_by(& &1.name)
    else
      user.characters
      |> Enum.filter(fn char -> char.active && !char.is_template end)
      |> Enum.sort_by(& &1.name)
    end
  end

  @doc """
  Handles autocomplete for the /link command's character parameter.
  Lists the user's characters in their current campaign.
  """
  def handle_link_autocomplete(interaction) do
    discord_id = interaction.user.id

    # Get the user's current input for the character name
    focused_option =
      interaction.data.options
      |> Enum.find(&Map.get(&1, :focused, false))

    input_value = if focused_option, do: focused_option.value || "", else: ""

    choices = build_link_autocomplete_choices(discord_id, input_value)

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
  Builds the autocomplete choices for the /link command.
  Returns a list of character choices for the user in their current campaign.
  """
  def build_link_autocomplete_choices(discord_id, input_value) do
    case Accounts.get_user_with_current_character(discord_id) do
      nil ->
        []

      user ->
        characters = get_user_characters_for_campaign(user)

        characters
        |> Enum.filter(fn char ->
          String.contains?(
            String.downcase(char.name),
            String.downcase(input_value)
          )
        end)
        |> Enum.take(25)
        |> Enum.map(fn char ->
          av = char.action_values || %{}
          char_type = av["Type"] || "PC"

          # Mark current character with a checkmark
          is_current = user.current_character_id == char.id
          marker = if is_current, do: " ✓", else: ""

          display_name = "#{char.name} (#{char_type})#{marker}"

          %{name: display_name, value: char.name}
        end)
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

    if is_nil(server_id) do
      respond(interaction, "This command can only be used in a server, not in DMs.",
        ephemeral: true
      )
    else
      message = build_stats_response(discord_id, server_id)
      respond(interaction, message, ephemeral: true)
    end
  end

  @doc """
  Builds the response message for the /stats command.
  Returns a string with the user's character stats in the current fight,
  or their current character's stats if no fight is active.
  """
  def build_stats_response(discord_id, server_id) do
    case Accounts.get_user_with_current_character(discord_id) do
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
        # No active fight - show current character stats if set
        build_stats_without_fight(user)

      fight_id ->
        build_stats_for_fight(user, fight_id)
    end
  end

  defp build_stats_without_fight(user) do
    case user.current_character do
      nil ->
        """
        There is no active fight in this server.
        You can set a current character with `/link` to view your stats anytime.
        """

      character ->
        header = "**Your Current Character**\n"
        header <> format_character_stats_standalone(character)
    end
  end

  defp build_stats_for_fight(user, fight_id) do
    # Get the fight with shots preloaded
    case Fights.get_fight_with_shots(fight_id) do
      nil ->
        "Fight not found."

      fight ->
        # Find the user's character shots in this fight
        user_shots = find_user_shots(fight, user)

        if Enum.empty?(user_shots) do
          "You don't have any characters in the fight \"#{fight.name}\"."
        else
          format_shot_stats(fight, user_shots)
        end
    end
  end

  defp find_user_shots(fight, user) do
    # Build a map of shot_id -> shot for quick driver lookup
    shots_by_id = Map.new(fight.shots, fn shot -> {shot.id, shot} end)

    fight.shots
    |> Enum.filter(fn shot ->
      cond do
        # Character shots: check if the character belongs to the user
        shot.character ->
          shot.character.user_id == user.id

        # Vehicle shots: check if the DRIVER of the vehicle belongs to the user
        shot.vehicle && shot.driver_id ->
          driver_shot = Map.get(shots_by_id, shot.driver_id)

          driver_shot && driver_shot.character &&
            driver_shot.character.user_id == user.id

        # Vehicle with no driver - don't show (or could check vehicle.user_id as fallback)
        true ->
          false
      end
    end)
    # Sort by most recently updated entity first
    |> Enum.sort_by(
      fn shot ->
        cond do
          shot.character -> shot.character.updated_at
          shot.vehicle -> shot.vehicle.updated_at
          true -> nil
        end
      end,
      &(DateTime.compare(&1 || DateTime.from_unix!(0), &2 || DateTime.from_unix!(0)) == :gt)
    )
  end

  defp format_shot_stats(fight, shots) do
    # Check if we have any vehicles
    # Note: With current filtering, vehicles always come with their driver character,
    # so we just need to check for vehicles to determine the header
    has_vehicles = Enum.any?(shots, & &1.vehicle)

    header =
      if has_vehicles do
        "**Your Characters & Vehicles in #{fight.name}**\n"
      else
        "**Your Characters in #{fight.name}**\n"
      end

    sections =
      shots
      |> Enum.map(&format_single_shot_stats/1)
      |> Enum.join("\n\n")

    header <> sections
  end

  defp format_single_shot_stats(shot) do
    cond do
      shot.character -> format_single_character_stats(shot)
      shot.vehicle -> format_single_vehicle_stats(shot)
      true -> "Unknown shot type"
    end
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

  defp format_single_vehicle_stats(shot) do
    vehicle = shot.vehicle
    av = vehicle.action_values || %{}

    # Get key vehicle stats
    acceleration = av["Acceleration"] || 0
    handling = av["Handling"] || 0
    squeal = av["Squeal"] || 0
    frame = av["Frame"] || 0
    chase_points = av["Chase Points"] || 0
    condition_points = av["Condition Points"] || 0
    impairments = shot.impairments || vehicle.impairments || 0

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

    # Build the vehicle section
    lines =
      [
        "🚗 **#{vehicle.name}** (#{av["Type"] || "Vehicle"})",
        shot_line,
        "Acceleration: **#{acceleration}** | Handling: **#{handling}**",
        "Squeal: **#{squeal}** | Frame: **#{frame}**",
        if(chase_points > 0, do: "Chase Points: **#{chase_points}**", else: nil),
        if(condition_points > 0, do: "Condition Points: **#{condition_points}**", else: nil),
        if(impairments > 0, do: "⚠️ Impairments: **#{impairments}**", else: nil),
        effects_line
      ]
      |> Enum.reject(&is_nil/1)

    Enum.join(lines, "\n")
  end

  # Formats a character's stats without a fight/shot context.
  # Used when displaying current character stats outside of an active fight.
  defp format_character_stats_standalone(character) do
    av = character.action_values || %{}

    # Get key combat stats
    wounds = av["Wounds"] || 0
    defense = av["Defense"] || 0
    toughness = av["Toughness"] || 0
    speed = av["Speed"] || 0
    fortune = av["Fortune"] || 0
    max_fortune = av["Max Fortune"] || 0
    impairments = character.impairments || 0

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

    # Build the character section (no shot position when not in a fight)
    lines =
      [
        "**#{character.name}** (#{av["Type"] || "PC"})",
        "Wounds: **#{wounds}** | Defense: **#{defense}** | Toughness: **#{toughness}**",
        "#{main_attack}: **#{main_attack_value}**",
        secondary_attack_line,
        "Speed: **#{speed}** | Fortune: **#{fortune}/#{max_fortune}**",
        if(impairments > 0, do: "⚠️ Impairments: **#{impairments}**", else: nil)
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

  @doc """
  Handles the /fortune command to spend Fortune points.
  """
  def handle_fortune(interaction) do
    discord_id = interaction.user.id
    server_id = interaction.guild_id

    if is_nil(server_id) do
      respond(interaction, "This command can only be used in a server, not in DMs.",
        ephemeral: true
      )
    else
      amount = get_option(interaction, "amount") || 1
      character_name = get_option(interaction, "character")
      message = build_fortune_response(discord_id, server_id, amount, character_name)
      respond(interaction, message, ephemeral: false)
    end
  end

  @doc """
  Handles autocomplete for the /fortune command's character parameter.
  Lists the user's characters in the current fight, sorted by most recently updated.
  """
  def handle_fortune_autocomplete(interaction) do
    discord_id = interaction.user.id
    server_id = interaction.guild_id

    # Get the user's current input for the character name
    focused_option =
      interaction.data.options
      |> Enum.find(&Map.get(&1, :focused, false))

    input_value = if focused_option, do: focused_option.value || "", else: ""

    choices = build_fortune_autocomplete_choices(discord_id, server_id, input_value)

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
  Builds the autocomplete choices for the /fortune command.
  Returns a list of character choices for the user in the current fight.
  """
  def build_fortune_autocomplete_choices(discord_id, server_id, input_value) do
    with user when not is_nil(user) <- Accounts.get_user_by_discord_id(discord_id),
         fight_id when not is_nil(fight_id) <- CurrentFight.get(server_id),
         fight when not is_nil(fight) <- Fights.get_fight_with_shots(fight_id) do
      user_shots = find_user_shots(fight, user)

      user_shots
      |> Enum.filter(fn shot ->
        String.contains?(
          String.downcase(shot.character.name),
          String.downcase(input_value)
        )
      end)
      |> Enum.take(25)
      |> Enum.map(fn shot ->
        char = shot.character
        av = char.action_values || %{}
        fortune = av["Fortune"] || 0
        max_fortune = av["Max Fortune"] || 0
        fortune_type = av["FortuneType"] || "Fortune"

        # Show name with fortune info: "Johnny Fist (Fortune: 5/8)"
        display_name = "#{char.name} (#{fortune_type}: #{fortune}/#{max_fortune})"

        %{name: display_name, value: char.name}
      end)
    else
      _ -> []
    end
  end

  @doc """
  Builds the response message for spending Fortune points.
  Takes discord_id, server_id, amount to spend, and optional character_name.
  If character_name is nil, uses the most recently updated character.
  Returns a formatted string message.
  """
  def build_fortune_response(discord_id, server_id, amount, character_name \\ nil) do
    case Accounts.get_user_by_discord_id(discord_id) do
      nil ->
        """
        Your Discord account is not linked to Chi War.
        Use `/link` to generate a link code.
        """

      user ->
        spend_fortune_for_user(user, server_id, amount, character_name)
    end
  end

  defp spend_fortune_for_user(user, server_id, amount, character_name) do
    case CurrentFight.get(server_id) do
      nil ->
        "There is no active fight in this server. Use `/start` to begin a fight."

      fight_id ->
        spend_fortune_in_fight(user, fight_id, amount, character_name)
    end
  end

  defp spend_fortune_in_fight(user, fight_id, amount, character_name) do
    case Fights.get_fight_with_shots(fight_id) do
      nil ->
        "Fight not found."

      fight ->
        user_shots = find_user_shots(fight, user)

        case user_shots do
          [] ->
            "You don't have any characters in the fight \"#{fight.name}\"."

          shots ->
            # Find the character by name, or use the first (most recently updated)
            shot = find_character_shot(shots, character_name)

            if shot do
              do_spend_fortune(shot.character, amount)
            else
              "Character \"#{character_name}\" not found in this fight."
            end
        end
    end
  end

  defp find_character_shot(shots, nil), do: List.first(shots)

  defp find_character_shot(shots, character_name) do
    Enum.find(shots, fn shot ->
      String.downcase(shot.character.name) == String.downcase(character_name)
    end) || List.first(shots)
  end

  defp do_spend_fortune(character, amount) do
    av = character.action_values || %{}
    current_fortune = av["Fortune"] || 0
    max_fortune = av["Max Fortune"] || 0
    fortune_type = av["FortuneType"] || "Fortune"

    cond do
      current_fortune <= 0 ->
        "**#{character.name}** has no #{fortune_type} points to spend! (#{current_fortune}/#{max_fortune})"

      amount > current_fortune ->
        "**#{character.name}** only has #{current_fortune} #{fortune_type} points, but you tried to spend #{amount}."

      true ->
        # Subtract amount (validation above ensures result is non-negative)
        # Defensive max() kept to prevent negative values in edge cases
        new_fortune = max(current_fortune - amount, 0)
        updated_av = Map.put(av, "Fortune", new_fortune)

        case Characters.update_character(character, %{"action_values" => updated_av}) do
          {:ok, _updated_character} ->
            "🎲 **#{character.name}** spent **#{amount}** #{fortune_type}! #{fortune_type} remaining: **#{new_fortune}/#{max_fortune}**"

          {:error, _reason} ->
            "Failed to update #{character.name}'s #{fortune_type} points. Please try again."
        end
    end
  end

  # Private helpers

  defp get_option(interaction, name) do
    case interaction.data.options do
      nil ->
        nil

      options ->
        options
        |> Enum.find(&(&1.name == name))
        |> case do
          nil -> nil
          option -> option.value
        end
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
