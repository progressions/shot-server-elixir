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

    case Req.get(url, [redirect: true]) do
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
      file_name: "#{String.downcase(entity_type)}_#{entity_id}_#{:os.system_time(:millisecond)}.jpg",
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
        Map.has_key?(entity, :description) && is_binary(entity.description) && entity.description != "" ->
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
    parts = [
      if(name, do: "Character named #{name}", else: nil),
      if(appearance && appearance != "", do: "Appearance: #{appearance}", else: nil),
      if(style && style != "", do: "Style: #{style}", else: nil),
      if(background && background != "", do: "Background: #{String.slice(background, 0..200)}", else: nil)
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
end
