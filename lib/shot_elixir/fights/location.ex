defmodule ShotElixir.Fights.Location do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "locations" do
    field :name, :string
    field :description, :string
    field :color, :string
    field :image_url, :string
    field :copied_from_location_id, :binary_id
    field :position_x, :integer, default: 0
    field :position_y, :integer, default: 0
    field :width, :integer, default: 200
    field :height, :integer, default: 150

    belongs_to :fight, ShotElixir.Fights.Fight
    belongs_to :site, ShotElixir.Sites.Site

    has_many :shots, ShotElixir.Fights.Shot, foreign_key: :location_id

    has_many :from_connections, ShotElixir.Fights.LocationConnection,
      foreign_key: :from_location_id

    has_many :to_connections, ShotElixir.Fights.LocationConnection, foreign_key: :to_location_id

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(location, attrs) do
    location
    |> cast(attrs, [
      :name,
      :description,
      :color,
      :image_url,
      :fight_id,
      :site_id,
      :copied_from_location_id,
      :position_x,
      :position_y,
      :width,
      :height
    ])
    |> validate_required([:name])
    |> validate_scope()
    |> unique_constraint(:name, name: :locations_fight_name_idx)
    |> unique_constraint(:name, name: :locations_site_name_idx)
  end

  defp validate_scope(changeset) do
    fight_id = get_field(changeset, :fight_id)
    site_id = get_field(changeset, :site_id)

    cond do
      fight_id != nil and site_id != nil ->
        add_error(changeset, :base, "cannot belong to both fight and site")

      fight_id == nil and site_id == nil ->
        add_error(changeset, :base, "must belong to either fight or site")

      true ->
        changeset
    end
  end

  @doc """
  Get the campaign_id for this location by deriving it from the parent fight or site.
  """
  def campaign_id(%__MODULE__{fight: %{campaign_id: id}}) when not is_nil(id), do: id
  def campaign_id(%__MODULE__{site: %{campaign_id: id}}) when not is_nil(id), do: id
  def campaign_id(_), do: nil
end
