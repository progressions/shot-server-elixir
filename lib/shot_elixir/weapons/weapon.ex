defmodule ShotElixir.Weapons.Weapon do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "weapons" do
    field :name, :string
    field :description, :string
    field :damage, :integer
    field :concealment, :integer
    field :reload_value, :integer
    field :juncture, :string
    field :mook_bonus, :integer, default: 0
    field :category, :string
    field :kachunk, :boolean, default: false
    field :image_url, :string, virtual: true
    field :active, :boolean, default: true

    belongs_to :campaign, ShotElixir.Campaigns.Campaign

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(weapon, attrs) do
    weapon
    |> cast(attrs, [
      :name,
      :description,
      :damage,
      :concealment,
      :reload_value,
      :juncture,
      :mook_bonus,
      :category,
      :kachunk,
      :active,
      :campaign_id
    ])
    |> validate_required([:name, :damage, :campaign_id])
    |> validate_number(:damage, greater_than_or_equal_to: 0)
    |> validate_number(:concealment, greater_than_or_equal_to: 0, less_than_or_equal_to: 5)
    |> validate_number(:mook_bonus, greater_than_or_equal_to: 0)
  end
end
