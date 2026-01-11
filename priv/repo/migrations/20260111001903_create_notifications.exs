defmodule ShotElixir.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :type, :string, null: false
      add :title, :string, null: false
      add :message, :text
      add :payload, :map, default: %{}
      add :read_at, :utc_datetime
      add :dismissed_at, :utc_datetime
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:notifications, [:user_id])
    create index(:notifications, [:user_id, :dismissed_at])
  end
end
