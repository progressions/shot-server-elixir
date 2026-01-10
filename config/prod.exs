import Config

# Do not print debug messages in production
config :logger, level: :info

# WebAuthn/Passkey configuration for production
config :shot_elixir, :webauthn_origin, "https://chiwar.net"
config :shot_elixir, :webauthn_rp_id, "chiwar.net"

# Frontend URL for magic link generation
config :shot_elixir, :frontend_url, "https://chiwar.net"

# CORS origins for production (no localhost)
config :shot_elixir, :cors_origins, [
  "https://chiwar.net",
  "https://shot-client-phoenix.fly.dev",
  "https://shot-client-next.fly.dev"
]

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
