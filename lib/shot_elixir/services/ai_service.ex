defmodule ShotElixir.Services.AiService do
  @moduledoc """
  Service for AI-powered operations like image generation and attachment.
  Provides functionality to download and attach images from URLs to entities.

  ## Provider Support
  This service supports multiple AI providers through the Provider behaviour:
    - `:grok` - xAI Grok API (default for legacy/fallback)
    - `:openai` - OpenAI API
    - `:gemini` - Google Gemini API

  The provider is selected based on the campaign's `ai_provider` setting.
  Each campaign owner stores their own credentials via the AiCredentials system.
  """

  require Logger
  alias ShotElixir.ActiveStorage
  alias ShotElixir.Services.ImageUploader
  alias ShotElixir.AI.Provider
  alias ShotElixir.AiCredentials
  alias ShotElixir.Characters
  alias ShotElixir.Vehicles
  alias ShotElixir.Parties
  alias ShotElixir.Factions
  alias ShotElixir.Sites
  alias ShotElixir.Weapons
  alias ShotElixir.Schticks
  alias ShotElixir.Fights
  alias ShotElixir.Campaigns

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
         {:ok, credential} <- get_credential_for_campaign(campaign),
         {:ok, prompt} <- build_character_prompt(description, campaign),
         {:ok, json} <- send_request_with_retry(credential, prompt, 1000, 3) do
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
         {:ok, credential} <- get_credential_for_campaign(character.campaign),
         {:ok, prompt} <- build_extend_character_prompt(character),
         {:ok, json} <- send_request_with_retry(credential, prompt, 1000, 3) do
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
        "Background" => non_empty(description["Background"], json["description"]),
        "Appearance" => non_empty(description["Appearance"], json["appearance"]),
        "Nicknames" => non_empty(description["Nicknames"], json["nicknames"]),
        "Melodramatic Hook" =>
          non_empty(description["Melodramatic Hook"], json["melodramaticHook"]),
        "Age" => non_empty(description["Age"], json["age"]),
        "Height" => non_empty(description["Height"], json["height"]),
        "Weight" => non_empty(description["Weight"], json["weight"]),
        "Hair Color" => non_empty(description["Hair Color"], json["hairColor"]),
        "Eye Color" => non_empty(description["Eye Color"], json["eyeColor"]),
        "Style of Dress" => non_empty(description["Style of Dress"], json["styleOfDress"])
      })

    wealth = non_empty(character.wealth, json["wealth"])

    %{character | description: updated_description, wealth: wealth}
  end

  # Helper to prefer non-empty values - uses existing value if present and non-empty,
  # otherwise falls back to the AI-generated value
  defp non_empty(existing, fallback) do
    cond do
      is_binary(existing) && String.trim(existing) != "" -> existing
      is_integer(existing) -> existing
      true -> fallback
    end
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
    with {:ok, temp_file} <- ImageUploader.download_image(image_url),
         {:ok, upload_result} <-
           ImageUploader.upload_to_imagekit(temp_file, entity_type, entity_id),
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

  @doc """
  Generates AI images for an entity using the configured AI provider.
  Downloads, stores in ImageKit, and creates database records for each image.
  Returns a list of ImageKit URLs (not temporary AI URLs).

  ## Parameters
    - entity_type: "Character", "Vehicle", etc.
    - entity_id: UUID of the entity
    - num_images: Number of images to generate (default 3)
    - opts: Optional keyword list with :user_id for tracking who generated

  ## Returns
    - {:ok, [imagekit_urls]} on success
    - {:error, reason} on failure
  """
  def generate_images_for_entity(entity_type, entity_id, num_images \\ 3, opts \\ []) do
    Logger.info("Generating #{num_images} AI images for #{entity_type}:#{entity_id}")

    # Get entity, campaign, credential, and prompt first
    with {:ok, entity} <- get_entity(entity_type, entity_id),
         {:ok, campaign} <- get_campaign_for_entity(entity_type, entity),
         {:ok, credential} <- get_credential_for_campaign(campaign),
         {:ok, prompt} <- build_image_prompt(entity) do
      # Now call generate_images with credential in scope for error handling
      case Provider.generate_images(credential, prompt, num_images, response_format: "url") do
        {:ok, urls} ->
          # Handle single URL vs list
          urls_list = if is_list(urls), do: urls, else: [urls]
          Logger.info("Successfully generated #{length(urls_list)} images from AI provider")

          # Store each image in ImageKit and create database records
          user_id = Keyword.get(opts, :user_id)

          stored_urls =
            urls_list
            |> Enum.map(fn url ->
              store_ai_generated_image(url, campaign.id, prompt, credential.provider, user_id)
            end)
            |> Enum.filter(&match?({:ok, _}, &1))
            |> Enum.map(fn {:ok, imagekit_url} -> imagekit_url end)

          if length(stored_urls) > 0 do
            Logger.info("Stored #{length(stored_urls)} images in ImageKit")
            {:ok, stored_urls}
          else
            Logger.error("Failed to store any generated images")
            {:error, "Failed to store generated images"}
          end

        {:error, :credit_exhausted, message} = error ->
          Logger.error("AI API credits exhausted: #{message}")
          # Mark the credential as suspended so user knows they need to update billing
          mark_credential_suspended(credential, message)
          error

        {:error, :rate_limited, message} ->
          Logger.warning("AI API rate limited: #{message}")
          {:error, :rate_limited, message}

        {:error, :server_error, message} ->
          Logger.error("AI API server error: #{message}")
          {:error, :server_error, message}

        {:error, reason} = error ->
          Logger.error("Failed to generate images: #{inspect(reason)}")
          error
      end
    else
      {:error, :no_credential} ->
        Logger.error("No AI credential configured for campaign")
        {:error, "No AI provider configured for this campaign"}

      {:error, reason} = error ->
        Logger.error("Failed to generate images: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Downloads an AI-generated image, uploads to ImageKit, and creates a database record.
  Returns the ImageKit URL for preview.
  """
  def store_ai_generated_image(ai_url, campaign_id, prompt, ai_provider, user_id) do
    alias ShotElixir.Media

    with {:ok, temp_file} <- ImageUploader.download_image(ai_url),
         {:ok, upload_result} <- upload_ai_image_to_imagekit(temp_file, campaign_id) do
      # Clean up temp file
      File.rm(temp_file)

      # Create database record as orphan
      attrs = %{
        campaign_id: campaign_id,
        status: "orphan",
        imagekit_file_id: upload_result.file_id,
        imagekit_url: upload_result.url,
        imagekit_file_path: upload_result.name,
        filename: Path.basename(upload_result.name),
        content_type: upload_result.metadata["fileType"] || "image/jpeg",
        byte_size: upload_result.size,
        width: upload_result.width,
        height: upload_result.height,
        prompt: prompt,
        ai_provider: ai_provider,
        generated_by_id: user_id
      }

      case Media.create_ai_image(attrs) do
        {:ok, _image} ->
          {:ok, upload_result.url}

        {:error, reason} ->
          Logger.error("Failed to create ai_generated_image record: #{inspect(reason)}")
          # Still return the URL even if DB record failed
          {:ok, upload_result.url}
      end
    else
      {:error, reason} ->
        Logger.error("Failed to store AI image: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp upload_ai_image_to_imagekit(file_path, campaign_id) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    filename = "ai-generated-#{timestamp}-#{:rand.uniform(9999)}.jpg"

    options = %{
      file_name: filename,
      folder: "/chi-war-#{environment()}/ai-generated/#{campaign_id}"
    }

    ShotElixir.Services.ImagekitService.upload_file(file_path, options)
  end

  defp environment do
    Application.get_env(:shot_elixir, :environment) || Mix.env() |> to_string()
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

  # Get the AI credential for a campaign based on its ai_provider setting
  defp get_credential_for_campaign(campaign) do
    AiCredentials.get_credential_for_campaign(campaign)
  end

  # Get the campaign for an entity (used for image generation)
  @campaign_entity_types ~w(Character Vehicle Party Faction Site Weapon Schtick Fight)

  defp get_campaign_for_entity(entity_type, entity)
       when entity_type in @campaign_entity_types do
    case entity.campaign_id do
      nil -> {:error, "#{entity_type} has no campaign"}
      campaign_id -> get_campaign_with_associations(campaign_id)
    end
  end

  defp get_campaign_for_entity(entity_type, _entity) do
    {:error, "Cannot determine campaign for entity type: #{entity_type}"}
  end

  # Send request with retry logic
  defp send_request_with_retry(credential, prompt, max_tokens, max_retries) do
    do_send_request_with_retry(credential, prompt, max_tokens, max_retries, 0)
  end

  defp do_send_request_with_retry(credential, prompt, max_tokens, max_retries, retry_count) do
    case Provider.send_chat_request(credential, prompt, max_tokens: max_tokens) do
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

            do_send_request_with_retry(
              credential,
              prompt,
              new_max_tokens,
              max_retries,
              retry_count + 1
            )

          {:error, reason} ->
            {:error, "Failed after #{retry_count + 1} attempts: #{inspect(reason)}"}
        end

      {:error, :credit_exhausted, message} ->
        Logger.error("AI API credits exhausted: #{message}")
        # Mark the credential as suspended so user knows they need to update billing
        mark_credential_suspended(credential, message)
        {:error, :credit_exhausted, message}

      {:error, :rate_limited, message} ->
        Logger.warning("AI API rate limited: #{message}")
        {:error, :rate_limited, message}

      {:error, reason} ->
        Logger.warning(
          "AI request failed (#{retry_count + 1}/#{max_retries}): #{inspect(reason)}"
        )

        {:error, "Failed after #{retry_count + 1} attempts: #{inspect(reason)}"}
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

  # Helper to mark a credential as suspended due to billing issues
  defp mark_credential_suspended(credential, message) do
    case AiCredentials.mark_suspended(credential, message) do
      {:ok, _credential} ->
        Logger.info("Credential #{credential.id} marked as suspended: #{message}")
        :ok

      {:error, changeset} ->
        Logger.error("Failed to mark credential as suspended: #{inspect(changeset)}")
        :error
    end
  end
end
