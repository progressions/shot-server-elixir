defmodule ShotElixir.Media.AiGeneratedImage do
  @moduledoc """
  Schema for tracking AI-generated images.

  Images can be:
  - "orphan" - Generated but not yet attached to an entity
  - "attached" - Associated with a character, vehicle, or other entity
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ["orphan", "attached"]

  schema "ai_generated_images" do
    field :entity_type, :string
    field :entity_id, :binary_id
    field :status, :string, default: "orphan"
    field :imagekit_file_id, :string
    field :imagekit_url, :string
    field :imagekit_file_path, :string
    field :filename, :string
    field :content_type, :string, default: "image/jpeg"
    field :byte_size, :integer
    field :width, :integer
    field :height, :integer
    field :prompt, :string
    field :ai_provider, :string

    belongs_to :campaign, ShotElixir.Campaigns.Campaign
    belongs_to :generated_by, ShotElixir.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(image, attrs) do
    image
    |> cast(attrs, [
      :campaign_id,
      :entity_type,
      :entity_id,
      :status,
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
      :generated_by_id
    ])
    |> validate_required([:campaign_id, :imagekit_file_id, :imagekit_url])
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:campaign_id)
    |> unique_constraint(:imagekit_file_id)
  end

  @doc """
  Changeset for attaching an orphan image to an entity.
  """
  def attach_changeset(image, entity_type, entity_id) do
    image
    |> cast(%{entity_type: entity_type, entity_id: entity_id}, [:entity_type, :entity_id])
    |> validate_required([:entity_type, :entity_id])
    |> put_change(:status, "attached")
  end

  @doc """
  Returns valid entity types that can have images attached.
  """
  def valid_entity_types do
    ["Character", "Vehicle", "Weapon", "Schtick", "Site", "Faction", "Party", "User"]
  end

  @doc """
  Generates a thumbnail URL with ImageKit transformations.
  """
  def thumbnail_url(%__MODULE__{imagekit_url: url}) when is_binary(url) do
    # Insert transformation before the file path
    # Format: https://ik.imagekit.io/id/chi-war-env/folder/file.jpg
    # Becomes: https://ik.imagekit.io/id/chi-war-env/tr:w-200,h-200,fo-auto/folder/file.jpg
    String.replace(url, "/chi-war-", "/tr:w-200,h-200,fo-auto/chi-war-")
  end

  def thumbnail_url(_), do: nil
end
