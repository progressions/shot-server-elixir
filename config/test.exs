import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
#
# DATABASE_URL can be used to override the default configuration
# for CI environments like GitHub Actions.
database_url = System.get_env("DATABASE_URL")

if database_url do
  config :shot_elixir, ShotElixir.Repo,
    url: database_url,
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
else
  config :shot_elixir, ShotElixir.Repo,
    username: "isaacpriestley",
    password: "",
    hostname: "localhost",
    database: "shot_server_test#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :shot_elixir, ShotElixirWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "oDNC43FHL7n6JJENXibkBmK2qT4iJn0APXLMWgnlq/3CA8bpStiEwyHGVjXPfZBs",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Email configuration for test environment
# Uses test adapter for assertions
config :shot_elixir, ShotElixir.Mailer, adapter: Swoosh.Adapters.Test

# URL options for email links in tests
config :shot_elixir, :mailer_url_options,
  scheme: "http",
  host: "localhost",
  port: 3001

# Disable Oban queues in test mode
config :shot_elixir, Oban,
  testing: :inline,
  plugins: [Oban.Plugins.Pruner]

# Nostrum Discord bot - not started in test (runtime: false + included_applications)
# No token needed since we don't start it

# Environment identifier for services like ImageUploader
config :shot_elixir, :environment, :test

# Avoid external ImageKit calls during tests
config :shot_elixir, :imagekit, disabled: true

# Avoid external Grok API calls during tests
config :shot_elixir, :grok, disabled: true

# Skip campaign seeding jobs in tests to avoid heavy background work
config :shot_elixir, :campaign_seeding, enabled: false

# Allow test image URLs used in fixtures
config :shot_elixir, :image_download, allowed_hosts: [~r/\.imagekit\.io$/, ~r/^example\.com$/]

# Grok API placeholder key for tests - prevents api_key() from raising
# Actual API calls will fail with 401/403 which is handled gracefully
config :shot_elixir, :grok, api_key: "test-placeholder-key"

# Notion API placeholder token for tests - prevents :no_notion_oauth_token errors
# Tests use stubbed clients so actual API calls aren't made
config :shot_elixir, :notion, token: "test-placeholder-notion-token"

# Notion HTTP client timeouts for tests - fast-fail on network calls
# This prevents tests from waiting 15s when they hit the real Notion API
# retry: false disables Req's automatic retry mechanism (default retries 3x with backoff)
config :shot_elixir, :notion_http,
  receive_timeout: 100,
  pool_timeout: 100,
  connect_timeout: 100,
  retry: false
