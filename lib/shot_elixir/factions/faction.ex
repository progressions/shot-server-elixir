defmodule ShotElixir.Factions.Faction do
  use Ecto.Schema
  import Ecto.Changeset
  use Arc.Ecto.Schema

  alias ShotElixir.Uploaders.ImageUploader
  alias ShotElixir.Services.ImagekitService

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "factions" do
    field :name, :string
    field :description, :string
    field :active, :boolean, default: true
    field :image, ImageUploader.Type
    field :image_url, :string, virtual: true
    field :image_data, :map, default: %{}

    belongs_to :campaign, ShotElixir.Campaigns.Campaign

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(faction, attrs) do
    faction
    |> cast(attrs, [:name, :description, :active, :image_data, :campaign_id])
    |> cast_attachments(attrs, [:image])
    |> validate_required([:name, :campaign_id])
    |> validate_length(:name, min: 1, max: 255)
  end

  @doc """
  Returns the image URL for a faction, using ImageKit if configured.
  """
  def image_url(%__MODULE__{} = faction) do
    cond do
      faction.image != nil ->
        ImageUploader.url({faction.image, faction})

      map_size(faction.image_data) > 0 ->
        ImagekitService.generate_url_from_metadata(faction.image_data)

      true ->
        nil
    end
  end
end
