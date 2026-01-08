# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :shot_elixir,
  ecto_repos: [ShotElixir.Repo],
  generators: [timestamp_type: :naive_datetime_usec]

# Configure Phoenix.Template to use HEEx engine for .heex templates
config :phoenix, :template_engines, heex: Phoenix.LiveView.HTMLEngine

# Configure Phoenix.Template to use HEEx engine for .heex templates
config :phoenix, :template_engines, heex: Phoenix.LiveView.HTMLEngine

# Configure Ecto for UUID primary keys and Rails compatibility
# Use separate migration table to avoid conflicts with Rails schema_migrations
config :shot_elixir, ShotElixir.Repo,
  migration_source: "ecto_migrations",
  migration_primary_key: [type: :binary_id],
  migration_foreign_key: [type: :binary_id]

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

# Guardian configuration - must match Rails Devise JWT secret for compatibility
config :shot_elixir, ShotElixir.Guardian,
  issuer: "shot_server",
  secret_key:
    "d18f1ac82f1db45a11fea843b4b75941433f1a3eded1e7b77f375ced770ef5c7611bd20a3a65706b1913f755024791804071dff7a32a0131e67acbc3fe1746a5",
  allowed_algos: ["HS256", "HS512"],
  verify_issuer: false

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

# Email configuration
config :shot_elixir, ShotElixir.Mailer, adapter: Swoosh.Adapters.Local

config :swoosh, :api_client, Swoosh.ApiClient.Finch

# Oban configuration for background jobs
config :shot_elixir, Oban,
  repo: ShotElixir.Repo,
  queues: [
    default: 10,
    emails: 20,
    high_priority: 5,
    notion: 3,
    discord: 10,
    images: 5
  ],
  plugins: [
    Oban.Plugins.Pruner,
    {Oban.Plugins.Cron,
     crontab: [
       # Clean up expired Discord link codes every 10 minutes
       {"*/10 * * * *", ShotElixir.Workers.LinkCodeCleanupWorker},
       # Clean up expired WebAuthn challenges every hour
       {"0 * * * *", ShotElixir.Workers.WebauthnChallengeCleanupWorker},
       # Clean up expired CLI authorization codes every hour
       {"0 * * * *", ShotElixir.Workers.CliAuthCodeCleanupWorker}
     ]}
  ]

# Discord configuration
# Token can be set via DISCORD_BOT_TOKEN env var or overridden in dev.exs/prod.exs
# Note: If no token is set, Nostrum won't start (see application.ex)
config :nostrum,
  token: System.get_env("DISCORD_BOT_TOKEN") || "placeholder",
  gateway_intents: [:guilds, :guild_messages, :message_content]

# Notion API configuration
# Note: token is loaded at runtime from .env via runtime.exs
# to ensure Dotenvy has loaded the .env file first
config :shot_elixir, :notion,
  database_id: "f6fa27ac-19cd-4b17-b218-55acc6d077be",
  factions_database_id: "0ae94bfa1a754c8fbda28ea50afa5fd5"

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
