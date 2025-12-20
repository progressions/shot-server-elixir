# Script for populating the database with seed data.
#
# Run with: mix run priv/repo/seeds.exs
#
# This script loads the master template data including:
# - The gamemaster user (progressions@gmail.com)
# - The Master Campaign (is_master_template: true)
# - All associated junctures, factions, schticks, weapons, characters, and character_schticks

alias ShotElixir.Repo

seed_file = Path.join(__DIR__, "seeds/master_template.sql")

if File.exists?(seed_file) do
  IO.puts("Loading seed data from #{seed_file}...")

  # Read and execute the SQL file
  sql = File.read!(seed_file)

  # Split by semicolons and execute each statement
  # Filter out empty statements and comments
  statements =
    sql
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn s ->
      s == "" ||
        String.starts_with?(s, "--") ||
        String.starts_with?(s, "/*")
    end)

  Enum.each(statements, fn statement ->
    # Skip pure comment lines
    lines = String.split(statement, "\n")

    non_comment_lines =
      Enum.reject(lines, fn line ->
        trimmed = String.trim(line)
        trimmed == "" || String.starts_with?(trimmed, "--")
      end)

    unless Enum.empty?(non_comment_lines) do
      try do
        Ecto.Adapters.SQL.query!(Repo, statement <> ";", [])
      rescue
        e in Postgrex.Error ->
          # Only ignore duplicate key errors (ON CONFLICT DO NOTHING handles this)
          # Re-raise all other errors to avoid silently suppressing real issues
          if e.postgres.code == "23505" do
            :ok
          else
            reraise e, __STACKTRACE__
          end
      end
    end
  end)

  IO.puts("Seed data loaded successfully!")

  # Print summary
  {:ok, result} = Repo.query("SELECT COUNT(*) FROM users")
  [[users]] = result.rows
  {:ok, result} = Repo.query("SELECT COUNT(*) FROM campaigns")
  [[campaigns]] = result.rows
  {:ok, result} = Repo.query("SELECT COUNT(*) FROM junctures")
  [[junctures]] = result.rows
  {:ok, result} = Repo.query("SELECT COUNT(*) FROM factions")
  [[factions]] = result.rows
  {:ok, result} = Repo.query("SELECT COUNT(*) FROM schticks")
  [[schticks]] = result.rows
  {:ok, result} = Repo.query("SELECT COUNT(*) FROM weapons")
  [[weapons]] = result.rows
  {:ok, result} = Repo.query("SELECT COUNT(*) FROM characters")
  [[characters]] = result.rows
  {:ok, result} = Repo.query("SELECT COUNT(*) FROM character_schticks")
  [[character_schticks]] = result.rows

  IO.puts("")
  IO.puts("Summary:")
  IO.puts("  Users: #{users}")
  IO.puts("  Campaigns: #{campaigns}")
  IO.puts("  Junctures: #{junctures}")
  IO.puts("  Factions: #{factions}")
  IO.puts("  Schticks: #{schticks}")
  IO.puts("  Weapons: #{weapons}")
  IO.puts("  Characters: #{characters}")
  IO.puts("  Character Schticks: #{character_schticks}")
else
  IO.puts("Seed file not found: #{seed_file}")
  IO.puts("Please ensure priv/repo/seeds/master_template.sql exists.")
end
