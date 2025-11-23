defmodule ShotElixir.Services.AiService do
  @moduledoc """
  Service for AI-powered operations like image generation and attachment.
  Provides functionality to download and attach images from URLs to entities.
  """

  require Logger
  alias ShotElixir.ActiveStorage
  alias ShotElixir.Services.{ImagekitService, GrokService}
  alias ShotElixir.Characters
  alias ShotElixir.Vehicles
  alias ShotElixir.Parties
  alias ShotElixir.Factions
  alias ShotElixir.Sites
  alias ShotElixir.Weapons
  alias ShotElixir.Schticks
  alias ShotElixir.Fights
  alias ShotElixir.Campaigns

  @max_prompt_length 1024

  @doc """
  Generates a new character using AI based on a description.

  ## Parameters
    - description: Text description of the character to create
    - campaign_id: UUID of the campaign

  ## Returns
    - {:ok, json_map} on success with character attributes
    - {:error, reason} on failure

  ## Examples
      iex> generate_character("A cyberpunk samurai", campaign_id)
      {:ok, %{"name" => "Jin Nakamura", "type" => "Featured Foe", ...}}
  """
  def generate_character(description, campaign_id) do
    with {:ok, campaign} <- get_campaign_with_associations(campaign_id),
         {:ok, prompt} <- build_character_prompt(description, campaign),
         {:ok, json} <- send_request_with_retry(prompt, 1000, 3) do
      if valid_character_json?(json) do
        {:ok, json}
      else
        {:error, "Invalid JSON structure"}
      end
    end
  end

  @doc """
  Extends an existing character with AI-generated details.

  ## Parameters
    - character_id: UUID of the character to extend

  ## Returns
    - {:ok, json_map} on success with additional character details
    - {:error, reason} on failure
  """
  def extend_character(character_id) do
    with {:ok, character} <- get_character_with_campaign(character_id),
         {:ok, prompt} <- build_extend_character_prompt(character),
         {:ok, json} <- send_request_with_retry(prompt, 1000, 3) do
      {:ok, json}
    end
  end

  @doc """
  Merges AI-generated JSON with an existing character's attributes.

  ## Parameters
    - json: Map of AI-generated character attributes
    - character: Existing character struct

  ## Returns
    - Updated character struct (not saved)
  """
  def merge_json_with_character(json, character) do
    description = character.description || %{}

    updated_description =
      Map.merge(description, %{
        "Background" => description["Background"] || json["description"],
        "Appearance" => description["Appearance"] || json["appearance"],
        "Nicknames" => description["Nicknames"] || json["nicknames"],
        "Melodramatic Hook" => description["Melodramatic Hook"] || json["melodramaticHook"],
        "Age" => description["Age"] || json["age"],
        "Height" => description["Height"] || json["height"],
        "Weight" => description["Weight"] || json["weight"],
        "Hair Color" => description["Hair Color"] || json["hairColor"],
        "Eye Color" => description["Eye Color"] || json["eyeColor"],
        "Style of Dress" => description["Style of Dress"] || json["styleOfDress"]
      })

    wealth = character.wealth || json["wealth"]

    %{character | description: updated_description, wealth: wealth}
  end

  @doc """
  Downloads an image from a URL and attaches it to an entity.

  ## Parameters
    - entity_type: "Character", "Vehicle", etc.
    - entity_id: UUID of the entity
    - image_url: URL to download the image from

  ## Returns
    - {:ok, attachment} on success
    - {:error, reason} on failure

  ## Examples
      iex> attach_image_from_url("Character", character_id, "https://example.com/image.jpg")
      {:ok, %Attachment{}}
  """
  def attach_image_from_url(entity_type, entity_id, image_url) when is_binary(image_url) do
    with {:ok, temp_file} <- download_image(image_url),
         {:ok, upload_result} <- upload_to_imagekit(temp_file, entity_type, entity_id),
         {:ok, attachment} <- ActiveStorage.attach_image(entity_type, entity_id, upload_result) do
      # Clean up temp file
      File.rm(temp_file)
      {:ok, attachment}
    else
      {:error, reason} = error ->
        Logger.error("Failed to attach image from URL: #{inspect(reason)}")
        error
    end
  end

  # Downloads image from URL to a temporary file
  defp download_image(url) do
    Logger.info("Downloading image from URL: #{url}")

    case Req.get(url, redirect: true) do
      {:ok, %{status: 200, body: body}} ->
        # Create temp file
        temp_path = Path.join(System.tmp_dir!(), "ai_image_#{:os.system_time(:millisecond)}.jpg")

        case File.write(temp_path, body) do
          :ok ->
            Logger.info("Image downloaded to: #{temp_path}")
            {:ok, temp_path}

          {:error, reason} ->
            {:error, "Failed to write temp file: #{inspect(reason)}"}
        end

      {:ok, %{status: status}} ->
        {:error, "HTTP request failed with status #{status}"}

      {:error, reason} ->
        {:error, "Failed to download image: #{inspect(reason)}"}
    end
  end

  # Uploads the downloaded image to ImageKit
  defp upload_to_imagekit(file_path, entity_type, entity_id) do
    Logger.info("Uploading image to ImageKit for #{entity_type}:#{entity_id}")

    plural_folder = pluralize_entity_type(String.downcase(entity_type))

    options = %{
      file_name:
        "#{String.downcase(entity_type)}_#{entity_id}_#{:os.system_time(:millisecond)}.jpg",
      folder: "/chi-war-#{Mix.env()}/#{plural_folder}"
    }

    ImagekitService.upload_file(file_path, options)
  end

  @doc """
  Generates AI images for an entity using Grok API.
  Returns a list of image URLs.

  ## Parameters
    - entity_type: "Character" or "Vehicle"
    - entity_id: UUID of the entity
    - num_images: Number of images to generate (default 3)

  ## Returns
    - {:ok, [urls]} on success
    - {:error, reason} on failure
  """
  def generate_images_for_entity(entity_type, entity_id, num_images \\ 3) do
    Logger.info("Generating #{num_images} AI images for #{entity_type}:#{entity_id}")

    with {:ok, entity} <- get_entity(entity_type, entity_id),
         {:ok, prompt} <- build_image_prompt(entity),
         {:ok, urls} <- GrokService.generate_image(prompt, num_images, "url") do
      Logger.info("Successfully generated #{length(urls)} images")
      {:ok, urls}
    else
      {:error, reason} = error ->
        Logger.error("Failed to generate images: #{inspect(reason)}")
        error
    end
  end

  # Get entity by type and ID
  defp get_entity("Character", entity_id) do
    case Characters.get_character(entity_id) do
      nil -> {:error, "Character not found"}
      character -> {:ok, character}
    end
  end

  defp get_entity("Vehicle", entity_id) do
    case Vehicles.get_vehicle(entity_id) do
      nil -> {:error, "Vehicle not found"}
      vehicle -> {:ok, vehicle}
    end
  end

  defp get_entity("Party", entity_id) do
    case Parties.get_party(entity_id) do
      nil -> {:error, "Party not found"}
      party -> {:ok, party}
    end
  end

  defp get_entity("Faction", entity_id) do
    case Factions.get_faction(entity_id) do
      nil -> {:error, "Faction not found"}
      faction -> {:ok, faction}
    end
  end

  defp get_entity("Site", entity_id) do
    case Sites.get_site(entity_id) do
      nil -> {:error, "Site not found"}
      site -> {:ok, site}
    end
  end

  defp get_entity("Weapon", entity_id) do
    case Weapons.get_weapon(entity_id) do
      nil -> {:error, "Weapon not found"}
      weapon -> {:ok, weapon}
    end
  end

  defp get_entity("Schtick", entity_id) do
    case Schticks.get_schtick(entity_id) do
      nil -> {:error, "Schtick not found"}
      schtick -> {:ok, schtick}
    end
  end

  defp get_entity("Fight", entity_id) do
    case Fights.get_fight(entity_id) do
      nil -> {:error, "Fight not found"}
      fight -> {:ok, fight}
    end
  end

  defp get_entity(entity_type, _entity_id) do
    {:error, "Unsupported entity type: #{entity_type}"}
  end

  # Build image generation prompt from entity
  defp build_image_prompt(entity) do
    prompt =
      cond do
        # Check description field first
        Map.has_key?(entity, :description) && is_binary(entity.description) &&
            entity.description != "" ->
          "Generate an image of: #{entity.description}"

        # Check action_values map - extract relevant fields
        Map.has_key?(entity, :action_values) && is_map(entity.action_values) ->
          build_prompt_from_action_values(entity.action_values, entity.name)

        # Fallback to name
        Map.has_key?(entity, :name) && entity.name ->
          "Generate an image of a character named #{entity.name}"

        true ->
          "Generate a character image"
      end

    {:ok, prompt}
  end

  # Build prompt from action_values map
  defp build_prompt_from_action_values(action_values, name) do
    # Extract relevant descriptive fields
    background = action_values["Background"] || action_values["background"]
    appearance = action_values["Appearance"] || action_values["appearance"]
    style = action_values["Style of Dress"] || action_values["style"]

    # Build description from available fields
    parts =
      [
        if(name, do: "Character named #{name}", else: nil),
        if(appearance && appearance != "", do: "Appearance: #{appearance}", else: nil),
        if(style && style != "", do: "Style: #{style}", else: nil),
        if(background && background != "",
          do: "Background: #{String.slice(background, 0..200)}",
          else: nil
        )
      ]
      |> Enum.reject(&is_nil/1)

    case parts do
      [] -> "Generate a character image"
      _ -> "Generate an image of: " <> Enum.join(parts, ". ")
    end
  end

  # Pluralize entity type names for folder paths
  defp pluralize_entity_type("party"), do: "parties"
  defp pluralize_entity_type(entity_type), do: entity_type <> "s"

  # Helper functions for character generation

  # Get campaign with preloaded associations
  defp get_campaign_with_associations(campaign_id) do
    case Campaigns.get_campaign(campaign_id) do
      nil ->
        {:error, "Campaign not found"}

      campaign ->
        # Preload factions and junctures
        campaign_with_assocs =
          ShotElixir.Repo.preload(campaign, [:factions, :junctures])

        {:ok, campaign_with_assocs}
    end
  end

  # Get character with preloaded campaign
  defp get_character_with_campaign(character_id) do
    case Characters.get_character(character_id) do
      nil ->
        {:error, "Character not found"}

      character ->
        character_with_campaign =
          ShotElixir.Repo.preload(character, campaign: [:factions, :junctures])

        {:ok, character_with_campaign}
    end
  end

  # Send request with retry logic
  defp send_request_with_retry(prompt, max_tokens, max_retries) do
    do_send_request_with_retry(prompt, max_tokens, max_retries, 0)
  end

  defp do_send_request_with_retry(prompt, max_tokens, max_retries, retry_count) do
    case GrokService.send_request(prompt, max_tokens) do
      {:ok, response} ->
        case parse_character_response(response) do
          {:ok, json} ->
            {:ok, json}

          {:error, "Incomplete response: truncated due to length"}
          when retry_count < max_retries ->
            Logger.warning(
              "AI response truncated due to length (#{retry_count + 1}/#{max_retries}). Retrying with increased max_tokens."
            )

            new_max_tokens = max_tokens + 1024
            Logger.info("Retrying with increased max_tokens: #{new_max_tokens}")
            do_send_request_with_retry(prompt, new_max_tokens, max_retries, retry_count + 1)

          {:error, reason} ->
            {:error, "Failed after #{retry_count} retries: #{inspect(reason)}"}
        end

      {:error, reason} ->
        Logger.warning(
          "AI request failed (#{retry_count + 1}/#{max_retries}): #{inspect(reason)}"
        )

        {:error, "Failed after #{retry_count} retries: #{inspect(reason)}"}
    end
  end

  # Parse character generation response
  defp parse_character_response(response) do
    case response do
      %{"choices" => [choice | _]} ->
        content = get_in(choice, ["message", "content"])
        finish_reason = choice["finish_reason"]

        cond do
          is_nil(content) || content == "" ->
            {:error, "Incomplete response: content empty"}

          finish_reason == "length" ->
            {:error, "Incomplete response: truncated due to length"}

          true ->
            case Jason.decode(content) do
              {:ok, json} ->
                {:ok, json}

              {:error, reason} ->
                {:error, "JSON parsing failed: #{inspect(reason)}"}
            end
        end

      _ ->
        {:error, "Unexpected response format: #{inspect(response)}"}
    end
  end

  # Validate character JSON structure
  defp valid_character_json?(json) do
    required_keys = [
      "name",
      "description",
      "type",
      "mainAttack",
      "attackValue",
      "defense",
      "toughness",
      "speed",
      "damage",
      "faction",
      "juncture",
      "nicknames",
      "age",
      "height",
      "weight",
      "hairColor",
      "eyeColor",
      "styleOfDress",
      "wealth",
      "appearance"
    ]

    Enum.all?(required_keys, &Map.has_key?(json, &1))
  end

  # Build prompt for new character generation
  defp build_character_prompt(description, campaign) do
    faction_names =
      case Enum.map(campaign.factions, & &1.name) do
        [] -> "None specified (use a generic faction)"
        names -> Enum.join(names, ", ")
      end

    juncture_names =
      case Enum.map(campaign.junctures, & &1.name) do
        [] -> "None specified (use a generic juncture)"
        names -> Enum.join(names, ", ")
      end

    prompt = """
    You are a creative AI character generator for a game of Feng Shui 2, the action movie roleplaying game.
    Based on the following description, create a detailed character profile:
    The character is a villain--not necessarily pure evil, but definitely an antagonist to the heroes.
    Determine if the villain is a Mook, Featured Foe, or Boss based on the description. Don't include the
    type in the description itself, but use it to determine the attributes. A Featured Foe is a significant
    antagonist with unique abilities and a backstory, while a Boss is a major villain with powerful abilities.
    If the character is a Mook, they should be a generic henchman with basic attributes. Never give
    Mooks unique names or detailed descriptions. If the character is a Featured Foe or Boss, provide a
    unique name and a detailed description of their personality, motivations, and background.
    Description: #{description}
    Include these attributes for the character:
    - Name
    - Description
    - Type: Mook, Featured Foe, or Boss
    - Main Attack: Either Guns, Sorcery, Martial Arts, Scroungetech, Genome, or Creature
    - Attack Value: A number between 13 and 16. A Mook has the attack value of 9. A Boss has an attack value of between 17 and 20.
    - Defense: A number between 13 and 16. A Mook has the defense value of 13. A Boss has a defense of between 17 and 20.
    - Toughness: A number between 5 and 8. A Mook has a null value. A Boss has a toughness of between 8 and 10.
    - Speed: A number between 5 and 8. A Mook has the speed of 6. A Boss has a speed of between 6 and 9.
    - Damage: A number between 7 and 12. A Mook has a damage value of 7.
    - Faction: The name of the faction the character belongs to, if not specified in the description. Use one of the following factions from the campaign: #{faction_names}.
    - Juncture: The name of the temporal juncture where the character originated, if not specified in the description. Use one of the following junctures: #{juncture_names}.
    - Nicknames: A comma-separated string
    - Age
    - Height (in feet and inches)
    - Weight (in pounds)
    - Hair Color
    - Eye Color
    - Style of Dress: A brief description of their clothing style
    - Wealth: Poor, Working Stiff, or Rich
    - Appearance: A short paragraph describing their physical appearance
    Respond with a JSON object describing the character, including all attributes. Use lowercase camelCase for keys.
    """

    {:ok, prompt}
  end

  # Build prompt for extending existing character
  defp build_extend_character_prompt(character) do
    background = get_in(character.description, ["Background"]) || ""
    type = get_in(character.action_values, ["Type"]) || ""
    archetype = get_in(character.action_values, ["Archetype"]) || ""

    faction_names =
      case Enum.map(character.campaign.factions, & &1.name) do
        [] -> "None specified (use a generic faction)"
        names -> Enum.join(names, ", ")
      end

    juncture_names =
      case Enum.map(character.campaign.junctures, & &1.name) do
        [] -> "None specified (use a generic juncture)"
        names -> Enum.join(names, ", ")
      end

    prompt = """
    You are a creative AI character generator for a game of Feng Shui 2, the action movie roleplaying game.
    Based on the following description, create a character profile, under 800 tokens.
    The character's name is #{character.name}, is a #{type}, #{archetype}.
    Don't include the type in the description itself, but use it to determine the attributes. A Featured Foe is a significant
    antagonist with unique abilities and a backstory, while a Boss is a major villain with powerful abilities.
    If the character is a Mook, they should be a generic henchman with basic attributes. Never give
    Mooks unique names or detailed descriptions. If the character is a PC or Featured Foe or Boss, provide a
    unique name and a detailed description of their personality, motivations, and background.
    Description: #{background}
    Include these attributes for the character:
    - Description: a short, concise description of the character's role and personality
    - Type: Mook, Featured Foe, or Boss
    - Faction: The name of the faction the character belongs to, if not specified in the description. Use one of the following factions from the campaign: #{faction_names}.
    - Juncture: The name of the temporal juncture where the character originated, if not specified in the description. Use one of the following junctures: #{juncture_names}.
    - Nicknames: A comma-separated string
    - Age
    - Height (in feet and inches)
    - Weight (in pounds)
    - Hair Color
    - Eye Color
    - Style of Dress: A short, concise, description of their clothing style
    - Wealth: Poor, Working Stiff, or Rich
    - Appearance: A short, concise sentence describing their physical appearance
    - Melodramatic Hook: A short, concise sentence describing the character's primary story goal.
    Respond with a JSON object (under 800 tokens) describing the character, including all attributes. Use lowercase camelCase for keys.
    """

    {:ok, prompt}
  end
end
