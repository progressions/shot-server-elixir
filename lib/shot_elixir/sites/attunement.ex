defmodule ShotElixir.Sites.Attunement do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}

  schema "attunements" do
    belongs_to :character, ShotElixir.Characters.Character, type: :binary_id
    belongs_to :site, ShotElixir.Sites.Site, type: :binary_id

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(attunement, attrs) do
    attunement
    |> cast(attrs, [:character_id, :site_id])
    |> validate_required([:character_id, :site_id])
    |> foreign_key_constraint(:character_id)
    |> foreign_key_constraint(:site_id)
    |> unique_constraint([:character_id, :site_id],
        name: :attunements_character_id_site_id_index,
        message: "Character already attuned to this site")
  end
end