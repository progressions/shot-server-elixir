defmodule ShotElixir.Fights do
  @moduledoc """
  The Fights context for managing combat encounters.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Fights.{Fight, Shot}

  def list_fights(campaign_id) do
    query = from f in Fight,
      where: f.campaign_id == ^campaign_id and f.active == true,
      order_by: [desc: f.updated_at]

    Repo.all(query)
  end

  def get_fight!(id), do: Repo.get!(Fight, id)
  def get_fight(id), do: Repo.get(Fight, id)

  def get_fight_with_shots(id) do
    Fight
    |> Repo.get(id)
    |> Repo.preload(shots: [:character, :vehicle])
  end

  def create_fight(attrs \\ %{}) do
    %Fight{}
    |> Fight.changeset(attrs)
    |> Repo.insert()
  end

  def update_fight(%Fight{} = fight, attrs) do
    fight
    |> Fight.changeset(attrs)
    |> Repo.update()
  end

  def delete_fight(%Fight{} = fight) do
    fight
    |> Ecto.Changeset.change(active: false)
    |> Repo.update()
  end

  def end_fight(%Fight{} = fight) do
    fight
    |> Ecto.Changeset.change(active: false, ended_at: DateTime.utc_now())
    |> Repo.update()
  end

  def touch_fight(%Fight{} = fight) do
    fight
    |> Ecto.Changeset.change(updated_at: DateTime.utc_now())
    |> Repo.update()
  end

  # Shot management
  def create_shot(attrs \\ %{}) do
    %Shot{}
    |> Shot.changeset(attrs)
    |> Repo.insert()
  end

  def update_shot(%Shot{} = shot, attrs) do
    shot
    |> Shot.changeset(attrs)
    |> Repo.update()
  end

  def delete_shot(%Shot{} = shot) do
    Repo.delete(shot)
  end

  def act_on_shot(%Shot{} = shot) do
    shot
    |> Ecto.Changeset.change(acted: true)
    |> Repo.update()
  end

  defmodule Fight do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: false}
    @foreign_key_type :binary_id

    schema "fights" do
      field :name, :string
      field :active, :boolean, default: true
      field :sequence, :integer, default: 1
      field :shot_counter, :integer, default: 18
      field :fight_type, :string, default: "fight"
      field :ended_at, :utc_datetime

      belongs_to :campaign, ShotElixir.Campaigns.Campaign
      belongs_to :location, ShotElixir.Sites.Site
      belongs_to :site, ShotElixir.Sites.Site

      has_many :shots, Shot
      has_many :character_effects, ShotElixir.Effects.CharacterEffect

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    def changeset(fight, attrs) do
      fight
      |> cast(attrs, [:name, :active, :sequence, :shot_counter, :fight_type,
                      :ended_at, :campaign_id, :location_id, :site_id])
      |> validate_required([:name, :campaign_id])
      |> validate_inclusion(:fight_type, ["fight", "chase"])
      |> validate_number(:shot_counter, greater_than_or_equal_to: 0)
      |> validate_number(:sequence, greater_than_or_equal_to: 1)
    end
  end

  defmodule Shot do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: false}
    @foreign_key_type :binary_id

    schema "shots" do
      field :shot, :integer
      field :acted, :boolean, default: false
      field :hidden, :boolean, default: false

      belongs_to :fight, Fight
      belongs_to :character, ShotElixir.Characters.Character
      belongs_to :vehicle, ShotElixir.Vehicles.Vehicle

      has_many :shot_drivers, ShotElixir.Fights.ShotDriver

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    def changeset(shot, attrs) do
      shot
      |> cast(attrs, [:shot, :acted, :hidden, :fight_id, :character_id, :vehicle_id])
      |> validate_required([:shot, :fight_id])
      |> validate_number(:shot, greater_than_or_equal_to: 0)
      |> validate_actor_presence()
    end

    defp validate_actor_presence(changeset) do
      character_id = get_field(changeset, :character_id)
      vehicle_id = get_field(changeset, :vehicle_id)

      cond do
        character_id == nil and vehicle_id == nil ->
          add_error(changeset, :base, "must have either character or vehicle")
        character_id != nil and vehicle_id != nil ->
          add_error(changeset, :base, "cannot have both character and vehicle")
        true ->
          changeset
      end
    end
  end

  defmodule ShotDriver do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: false}
    @foreign_key_type :binary_id

    schema "shot_drivers" do
      belongs_to :shot, Shot
      belongs_to :character, ShotElixir.Characters.Character

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    def changeset(shot_driver, attrs) do
      shot_driver
      |> cast(attrs, [:shot_id, :character_id])
      |> validate_required([:shot_id, :character_id])
      |> unique_constraint([:shot_id, :character_id])
    end
  end
end