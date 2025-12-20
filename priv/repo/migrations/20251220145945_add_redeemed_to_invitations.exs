defmodule ShotElixir.Repo.Migrations.AddRedeemedToInvitations do
  use Ecto.Migration

  def change do
    alter table(:invitations) do
      add :redeemed, :boolean, default: false, null: false
      add :redeemed_at, :naive_datetime
    end
  end
end
