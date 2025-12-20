defmodule ShotElixir.Repo.Migrations.AddOnDeleteToCharacterEffects do
  use Ecto.Migration

  @moduledoc """
  Adds ON DELETE CASCADE to character_effects.shot_id foreign key.

  This migration handles three scenarios:
  1. Fresh Elixir setup (via baseline migration) - FK already has on_delete: :delete_all, skip
  2. Rails setup (via structure.sql) - FK named fk_rails_1163db7ee4, needs update
  3. Legacy Elixir setup - FK named character_effects_shot_id_fkey, needs update
  """

  def up do
    # Check if this is a fresh setup where baseline already created the correct FK
    # The baseline migration creates the FK with on_delete: :delete_all
    # We can detect a fresh setup by checking if the Rails-style FK doesn't exist
    cond do
      constraint_exists?("fk_rails_1163db7ee4") ->
        # Rails setup - drop Rails FK and recreate with on_delete
        drop constraint(:character_effects, "fk_rails_1163db7ee4")

        alter table(:character_effects) do
          modify :shot_id, references(:shots, type: :uuid, on_delete: :delete_all)
        end

      constraint_exists?("character_effects_shot_id_fkey") ->
        # Check if it already has ON DELETE CASCADE (fresh setup)
        if has_on_delete_cascade?() do
          # Fresh Elixir setup - already correct, nothing to do
          :ok
        else
          # Legacy Elixir setup without on_delete - recreate
          drop constraint(:character_effects, "character_effects_shot_id_fkey")

          alter table(:character_effects) do
            modify :shot_id, references(:shots, type: :uuid, on_delete: :delete_all)
          end
        end

      true ->
        # No FK exists yet (shouldn't happen, but handle gracefully)
        alter table(:character_effects) do
          modify :shot_id, references(:shots, type: :uuid, on_delete: :delete_all)
        end
    end
  end

  def down do
    # Always use Ecto naming for rollback
    if constraint_exists?("character_effects_shot_id_fkey") do
      drop constraint(:character_effects, "character_effects_shot_id_fkey")

      alter table(:character_effects) do
        modify :shot_id, references(:shots, type: :uuid, on_delete: :nothing)
      end
    end
  end

  defp constraint_exists?(constraint_name) do
    query = """
    SELECT EXISTS (
      SELECT 1 FROM information_schema.table_constraints
      WHERE constraint_name = '#{constraint_name}'
      AND table_name = 'character_effects'
    )
    """

    %{rows: [[exists]]} = repo().query!(query)
    exists
  end

  defp has_on_delete_cascade?() do
    query = """
    SELECT confdeltype = 'c'
    FROM pg_constraint
    WHERE conname = 'character_effects_shot_id_fkey'
    AND conrelid = 'character_effects'::regclass
    """

    case repo().query!(query) do
      %{rows: [[true]]} -> true
      _ -> false
    end
  end
end
