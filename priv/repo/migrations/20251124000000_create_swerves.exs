defmodule ShotElixir.Repo.Migrations.CreateSwerves do
  use Ecto.Migration

  def change do
    create table(:swerves, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :positives_sum, :integer, null: false
      add :positives_rolls, {:array, :integer}, null: false
      add :negatives_sum, :integer, null: false
      add :negatives_rolls, {:array, :integer}, null: false
      add :total, :integer, null: false
      add :boxcars, :boolean, default: false, null: false
      add :rolled_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:swerves, [:username])
    create index(:swerves, [:rolled_at])
  end
end
