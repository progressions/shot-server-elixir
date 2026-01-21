defmodule ShotElixir.Repo.Migrations.AddGinIndexesToMentions do
  use Ecto.Migration

  @tables ~w(characters sites parties factions junctures adventures)a

  def change do
    Enum.each(@tables, fn table ->
      index_name = :"#{table}_mentions_gin_index"

      create_if_not_exists(index(table, [:mentions], using: :gin, name: index_name))
    end)
  end
end
