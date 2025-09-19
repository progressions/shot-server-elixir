# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :shot_elixir,
  ecto_repos: [ShotElixir.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configures the endpoint
config :shot_elixir, ShotElixirWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: ShotElixirWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: ShotElixir.PubSub,
  live_view: [signing_salt: "aYdBc9Wn"]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Guardian configuration
config :shot_elixir, ShotElixir.Guardian,
  issuer: "shot_server",
  secret_key: "your_secret_key_here"

# ImageKit configuration
config :shot_elixir, :imagekit,
  private_key: System.get_env("IMAGEKIT_PRIVATE_KEY"),
  public_key: System.get_env("IMAGEKIT_PUBLIC_KEY"),
  id: System.get_env("IMAGEKIT_ID") || "nvqgwnjgv",
  url_endpoint: "https://ik.imagekit.io/nvqgwnjgv",
  environment: config_env()

# Arc configuration for file uploads
config :arc,
  storage: Arc.Storage.Local

# Cachex configuration for image URL caching
config :shot_elixir, :cachex,
  caches: [
    image_cache: [
      limit: 10_000,
      ttl: :timer.hours(1)
    ]
  ]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
