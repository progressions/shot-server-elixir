defmodule ShotElixir.Repo.Migrations.AddUserIdToFights do
  use Ecto.Migration

  def change do
    alter table(:fights) do
      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)
    end

    create index(:fights, [:user_id])
  end
end
