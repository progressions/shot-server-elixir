defmodule ShotElixir.Repo.Migrations.MigrateLocationStringsToRecords do
  use Ecto.Migration
  import Ecto.Query

  @doc """
  Migrates existing shot.location strings to proper Location records.

  For each fight:
  1. Find distinct location strings (case-insensitive, trimmed)
  2. Create a Location record for each unique name
  3. Update shots to reference the new location_id

  Edge cases:
  - nil/empty location strings are skipped
  - Whitespace is trimmed
  - Names are matched case-insensitively
  - Migration is idempotent (safe to re-run)
  """

  def up do
    # Get all fights that have shots with non-empty location strings
    fights_with_locations =
      repo().all(
        from(s in "shots",
          where: not is_nil(s.location) and s.location != "",
          select: s.fight_id,
          distinct: true
        )
      )

    IO.puts("Found #{length(fights_with_locations)} fights with location strings")

    for fight_id <- fights_with_locations do
      migrate_fight_locations(fight_id)
    end

    # Verify migration
    remaining =
      repo().one(
        from(s in "shots",
          where: not is_nil(s.location) and s.location != "" and is_nil(s.location_id),
          select: count(s.id)
        )
      )

    if remaining > 0 do
      IO.puts("WARNING: #{remaining} shots still have location string but no location_id")
    else
      IO.puts("Migration complete: all location strings converted to Location records")
    end
  end

  def down do
    # Clear location_id from all shots (locations will be cascade deleted or cleaned separately)
    repo().update_all("shots", set: [location_id: nil])

    # Delete all locations that were created (those with fight_id set)
    repo().delete_all(from(l in "locations", where: not is_nil(l.fight_id)))

    IO.puts("Rolled back: cleared location_id from shots and deleted fight locations")
  end

  defp migrate_fight_locations(fight_id) do
    # Get distinct location names for this fight (case-insensitive, trimmed)
    location_names =
      repo().all(
        from(s in "shots",
          where: s.fight_id == ^fight_id and not is_nil(s.location) and s.location != "",
          select: fragment("DISTINCT lower(trim(?))", s.location)
        )
      )

    {:ok, fight_id_str} = Ecto.UUID.load(fight_id)
    IO.puts("  Fight #{fight_id_str}: #{length(location_names)} unique locations")

    for name <- location_names do
      # Skip empty strings after trim
      if name != "" do
        # Check if location already exists for this fight
        existing =
          repo().one(
            from(l in "locations",
              where: l.fight_id == ^fight_id and fragment("lower(?)", l.name) == ^name,
              select: l.id
            )
          )

        location_id =
          case existing do
            nil ->
              # Create new location - use the original casing from first shot found
              original_name =
                repo().one(
                  from(s in "shots",
                    where:
                      s.fight_id == ^fight_id and
                        fragment("lower(trim(?)) = ?", s.location, ^name),
                    select: fragment("trim(?)", s.location),
                    limit: 1
                  )
                )

              now = DateTime.utc_now() |> DateTime.truncate(:second)

              {1, [%{id: id}]} =
                repo().insert_all(
                  "locations",
                  [
                    %{
                      id: Ecto.UUID.bingenerate(),
                      name: original_name,
                      fight_id: fight_id,
                      created_at: now,
                      updated_at: now
                    }
                  ],
                  returning: [:id]
                )

              id

            id ->
              # Location already exists
              id
          end

        # Update all shots with this location name to reference the location
        {count, _} =
          repo().update_all(
            from(s in "shots",
              where:
                s.fight_id == ^fight_id and
                  fragment("lower(trim(?)) = ?", s.location, ^name) and
                  is_nil(s.location_id)
            ),
            set: [location_id: location_id]
          )

        if count > 0 do
          IO.puts("    - \"#{name}\": #{count} shots updated")
        end
      end
    end
  end
end
