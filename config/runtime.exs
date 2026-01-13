import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# Load .env file in dev/test environments
if config_env() in [:dev, :test] do
  if Code.ensure_loaded?(Dotenvy) do
    Dotenvy.source!([".env", System.get_env()])
    |> Enum.each(fn {key, value} ->
      System.put_env(key, value)
    end)
  end
end

# Discord bot configuration - loaded from environment variables
# Must be set AFTER dotenvy loads .env above
if discord_token = System.get_env("DISCORD_TOKEN") do
  config :nostrum, token: discord_token
end

# Notion API configuration - token loaded from environment variables
# Must be set AFTER dotenvy loads .env above
# Note: database_id, factions_database_id, and periodic_sync_enabled are defined in config.exs
# No longer using compile_env, so runtime config can differ
if notion_token = System.get_env("NOTION_TOKEN") do
  config :shot_elixir, :notion,
    # Characters database (main database)
    database_id: "f6fa27ac-19cd-4b17-b218-55acc6d077be",
    # Factions database
    factions_database_id: "0ae94bfa1a754c8fbda28ea50afa5fd5",
    # Parties database
    parties_database_id: "2e5e0b55d4178083bd93e8a60280209b",
    # Sites/Locations database
    sites_database_id: "8ac4e657c540499c977f79b0643b7070",
    # Junctures database
    junctures_database_id: "4228eb7fefef470bb9f19a7f5d73c0fc",
    periodic_sync_enabled: true,
    token: notion_token
end

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/shot_elixir start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :shot_elixir, ShotElixirWeb.Endpoint, server: true
end

# Environment identifier for services like ImageUploader
config :shot_elixir, :environment, config_env()

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :shot_elixir, ShotElixir.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :shot_elixir, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :shot_elixir, ShotElixirWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    check_origin: [
      "https://chiwar.net",
      "https://shot-client-phoenix.fly.dev",
      "https://shot-client-next.fly.dev"
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :shot_elixir, ShotElixirWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :shot_elixir, ShotElixirWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # Email configuration for production
  # Uses Mailgun HTTP API
  config :shot_elixir, ShotElixir.Mailer,
    adapter: Swoosh.Adapters.Mailgun,
    api_key: System.get_env("MAILGUN_API_KEY"),
    domain: System.get_env("MAILGUN_DOMAIN"),
    base_url: "https://api.mailgun.net/v3"

  # URL options for email links in production
  config :shot_elixir, :mailer_url_options,
    scheme: "https",
    host: "chiwar.net",
    port: nil

  # Frontend URL for magic links in production
  config :shot_elixir, :frontend_url, "https://chiwar.net"

  # Google OAuth configuration for Gemini AI provider
  # Client ID and secret are loaded from environment variables in the controller
  # This config provides the callback URL and frontend URL for redirects
  config :shot_elixir, :google_oauth,
    callback_url: "https://shot-elixir.fly.dev/auth/google/callback",
    frontend_url: "https://chiwar.net"
end
