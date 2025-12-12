defmodule ShotElixir.Repo.Migrations.AddExtendingToCharacters do
  use Ecto.Migration

  def change do
    alter table(:characters) do
      add :extending, :boolean, default: false, null: false
    end
  end
end
