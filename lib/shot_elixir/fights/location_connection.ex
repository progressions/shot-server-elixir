defmodule ShotElixir.Fights.LocationConnection do
  @moduledoc """
  Schema for connections (edges) between locations.
  Used in the visual location editor to show paths between areas.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ShotElixir.Fights.Location
  alias ShotElixir.Repo

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "location_connections" do
    field :bidirectional, :boolean, default: true
    field :label, :string

    belongs_to :from_location, Location
    belongs_to :to_location, Location

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(connection, attrs) do
    connection
    |> cast(attrs, [:from_location_id, :to_location_id, :bidirectional, :label])
    |> validate_required([:from_location_id, :to_location_id])
    |> foreign_key_constraint(:from_location_id)
    |> foreign_key_constraint(:to_location_id)
    |> validate_not_self_connection()
    |> normalize_bidirectional_order()
  end

  # Validates that a connection doesn't connect a location to itself.
  defp validate_not_self_connection(changeset) do
    from_id = get_field(changeset, :from_location_id)
    to_id = get_field(changeset, :to_location_id)

    if from_id && to_id && from_id == to_id do
      add_error(changeset, :to_location_id, "cannot connect location to itself")
    else
      changeset
    end
  end

  # For bidirectional connections, normalize the order so the lower UUID
  # is always from_location_id. This prevents duplicate edges like A↔B and B↔A.
  defp normalize_bidirectional_order(changeset) do
    bidirectional = get_field(changeset, :bidirectional)
    from_id = get_field(changeset, :from_location_id)
    to_id = get_field(changeset, :to_location_id)

    if bidirectional && from_id && to_id && from_id > to_id do
      changeset
      |> put_change(:from_location_id, to_id)
      |> put_change(:to_location_id, from_id)
    else
      changeset
    end
  end

  @doc """
  Validates that both locations belong to the same fight or same site.
  Must be called after the changeset is valid and IDs are set.
  Returns {:ok, changeset} or {:error, changeset}.
  """
  def validate_same_scope(changeset) do
    from_id = get_field(changeset, :from_location_id)
    to_id = get_field(changeset, :to_location_id)

    if from_id && to_id do
      from_location = Repo.get(Location, from_id)
      to_location = Repo.get(Location, to_id)

      cond do
        is_nil(from_location) ->
          {:error, add_error(changeset, :from_location_id, "location not found")}

        is_nil(to_location) ->
          {:error, add_error(changeset, :to_location_id, "location not found")}

        from_location.fight_id && from_location.fight_id == to_location.fight_id ->
          {:ok, changeset}

        from_location.site_id && from_location.site_id == to_location.site_id ->
          {:ok, changeset}

        true ->
          {:error,
           add_error(
             changeset,
             :to_location_id,
             "locations must belong to the same fight or site"
           )}
      end
    else
      {:ok, changeset}
    end
  end
end
