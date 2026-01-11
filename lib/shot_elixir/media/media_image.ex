defmodule ShotElixir.Media.MediaImage do
  @moduledoc """
  Schema for tracking all images in the media library.

  This includes both manually uploaded images and AI-generated images.
  Images can be:
  - "orphan" - Not yet attached to an entity
  - "attached" - Associated with a character, vehicle, or other entity
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ["orphan", "attached"]
  @sources ["upload", "ai_generated"]

  schema "media_images" do
    # Source: "upload" or "ai_generated"
    field :source, :string

    # Entity attachment
    field :entity_type, :string
    field :entity_id, :binary_id
    field :status, :string, default: "orphan"

    # Link to ActiveStorage blob (when attached)
    field :active_storage_blob_id, :integer

    # ImageKit data
    field :imagekit_file_id, :string
    field :imagekit_url, :string
    field :imagekit_file_path, :string

    # File metadata
    field :filename, :string
    field :content_type, :string, default: "image/jpeg"
    field :byte_size, :integer
    field :width, :integer
    field :height, :integer

    # AI-specific metadata (optional)
    field :prompt, :string
    field :ai_provider, :string

    # AI-generated tags from ImageKit (Google Vision / AWS Rekognition)
    # Format: [%{"name" => "warrior", "confidence" => 95.5, "source" => "google-auto-tagging"}, ...]
    field :ai_tags, {:array, :map}, default: []

    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :generated_by, ShotElixir.Accounts.User
    belongs_to :uploaded_by, ShotElixir.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(image, attrs) do
    image
    |> cast(attrs, [
      :campaign_id,
      :source,
      :entity_type,
      :entity_id,
      :status,
      :active_storage_blob_id,
      :imagekit_file_id,
      :imagekit_url,
      :imagekit_file_path,
      :filename,
      :content_type,
      :byte_size,
      :width,
      :height,
      :prompt,
      :ai_provider,
      :ai_tags,
      :generated_by_id,
      :uploaded_by_id
    ])
    |> validate_required([:campaign_id, :source, :imagekit_file_id, :imagekit_url])
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:source, @sources)
    |> foreign_key_constraint(:campaign_id)
    |> unique_constraint(:imagekit_file_id)
  end

  @doc """
  Changeset for creating an uploaded image record.
  """
  def upload_changeset(attrs) do
    %__MODULE__{}
    |> changeset(Map.put(attrs, :source, "upload"))
  end

  @doc """
  Changeset for creating an AI-generated image record.
  """
  def ai_generated_changeset(attrs) do
    %__MODULE__{}
    |> changeset(Map.put(attrs, :source, "ai_generated"))
  end

  @doc """
  Changeset for attaching an orphan image to an entity.
  """
  def attach_changeset(image, entity_type, entity_id, blob_id \\ nil) do
    changes = %{
      entity_type: entity_type,
      entity_id: entity_id,
      status: "attached"
    }

    changes =
      if blob_id do
        Map.put(changes, :active_storage_blob_id, blob_id)
      else
        changes
      end

    image
    |> cast(changes, [:entity_type, :entity_id, :status, :active_storage_blob_id])
    |> validate_required([:entity_type, :entity_id])
    |> validate_inclusion(:entity_type, valid_entity_types(),
      message: "must be one of: #{Enum.join(valid_entity_types(), ", ")}"
    )
  end

  @doc """
  Returns valid entity types that can have images attached.
  """
  def valid_entity_types do
    ["Character", "Vehicle", "Weapon", "Schtick", "Site", "Faction", "Party", "User"]
  end

  @doc """
  Returns valid source types.
  """
  def valid_sources do
    @sources
  end

  @doc """
  Generates a thumbnail URL with ImageKit transformations.
  """
  def thumbnail_url(%__MODULE__{imagekit_url: url}) when is_binary(url) do
    # Insert transformation before the file path
    # Format: https://ik.imagekit.io/id/chi-war-env/folder/file.jpg
    # Becomes: https://ik.imagekit.io/id/chi-war-env/tr:w-200,h-200,fo-auto/folder/file.jpg

    # Try chi-war- pattern first, then fall back to regex for other formats
    cond do
      String.contains?(url, "/chi-war-") ->
        String.replace(url, "/chi-war-", "/tr:w-200,h-200,fo-auto/chi-war-")

      true ->
        # Regex pattern to match ImageKit URL format: ik.imagekit.io/ID/path
        # Insert transformation after the ID segment
        case Regex.run(~r{^(https?://ik\.imagekit\.io/[^/]+/)(.+)$}, url) do
          [_full, base, path] ->
            base <> "tr:w-200,h-200,fo-auto/" <> path

          nil ->
            # If URL doesn't match expected format, return original URL
            url
        end
    end
  end

  def thumbnail_url(_), do: nil
end
