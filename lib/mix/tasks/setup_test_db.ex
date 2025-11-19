defmodule Mix.Tasks.SetupTestDb do
  @moduledoc """
  Loads the Rails schema dump into the test database.

  This task is designed for CI environments where we need to set up
  the database schema without running Rails migrations.
  """

  use Mix.Task

  @shortdoc "Load Rails schema dump into test database"

  def run(_args) do
    Mix.Task.run("app.config")

    # Get database config
    repo_config = Application.get_env(:shot_elixir, ShotElixir.Repo)

    database = repo_config[:database]
    username = repo_config[:username]
    password = repo_config[:password] || ""
    hostname = repo_config[:hostname] || "localhost"
    port = repo_config[:port] || 5432

    schema_file = "priv/repo/structure.sql"

    unless File.exists?(schema_file) do
      Mix.raise("Schema file not found: #{schema_file}")
    end

    Mix.shell().info("Creating database #{database}...")

    # Create database if it doesn't exist
    create_cmd =
      build_psql_cmd(
        username,
        password,
        hostname,
        port,
        "postgres",
        "CREATE DATABASE \"#{database}\";"
      )

    case System.cmd("psql", create_cmd, stderr_to_stdout: true) do
      {_output, 0} ->
        Mix.shell().info("Database created successfully")

      {output, _code} ->
        if String.contains?(output, "already exists") do
          Mix.shell().info("Database already exists")
        else
          Mix.shell().info("Create database result: #{output}")
        end
    end

    Mix.shell().info("Loading schema from #{schema_file}...")

    # Load schema
    load_cmd = build_psql_cmd(username, password, hostname, port, database, nil)

    case System.cmd("psql", load_cmd ++ ["<", schema_file],
           stderr_to_stdout: true,
           into: IO.stream(:stdio, :line)
         ) do
      {_, 0} ->
        Mix.shell().info("Schema loaded successfully")

      {_, code} ->
        Mix.shell().info(
          "Schema load completed with code #{code} (some errors expected if tables already exist)"
        )
    end
  end

  defp build_psql_cmd(username, password, hostname, port, database, sql) do
    cmd = ["-h", hostname, "-p", to_string(port), "-U", username, "-d", database]

    cmd =
      if password != "" do
        # Set PGPASSWORD environment variable if password is provided
        System.put_env("PGPASSWORD", password)
        cmd
      else
        cmd
      end

    if sql do
      cmd ++ ["-c", sql]
    else
      cmd
    end
  end
end
