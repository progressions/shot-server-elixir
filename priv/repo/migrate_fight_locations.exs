import Ecto.Query
alias ShotElixir.Repo
alias ShotElixir.Fights.{Shot, Location}

args = System.argv()

fight_id =
  case args do
    [id | _] ->
      id

    _ ->
      IO.puts(:stderr, "Usage: mix run priv/repo/migrate_fight_locations.exs <fight_id>")
      System.halt(1)
  end

# Get unique location strings from shots in this fight
location_strings = Repo.all(
  from s in Shot,
  where: s.fight_id == ^fight_id and not is_nil(s.location),
  distinct: true,
  select: s.location
) |> Enum.reject(&(&1 == ""))

IO.puts("Found #{length(location_strings)} unique location strings: #{inspect(location_strings)}")

# Create Location records for each unique string
location_map = Enum.reduce(location_strings, %{}, fn name, acc ->
  {:ok, location} = %Location{}
    |> Location.changeset(%{name: name, fight_id: fight_id})
    |> Repo.insert()

  IO.puts("Created Location: #{name} (#{location.id})")
  Map.put(acc, name, location.id)
end)

# Update shots to use location_id
updated_count = Enum.reduce(location_strings, 0, fn name, count ->
  location_id = Map.get(location_map, name)

  {num, _} = Repo.update_all(
    from(s in Shot,
      where: s.fight_id == ^fight_id and s.location == ^name),
    set: [location_id: location_id]
  )

  IO.puts("Updated #{num} shots with location \"#{name}\"")
  count + num
end)

IO.puts("\nMigration complete!")
IO.puts("Created #{length(location_strings)} Location records")
IO.puts("Updated #{updated_count} shots with location_id references")
