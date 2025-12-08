import Config

# Do not print debug messages in production
config :logger, level: :info

# WebAuthn/Passkey configuration for production
config :shot_elixir, :webauthn_origin, "https://chiwar.net"
config :shot_elixir, :webauthn_rp_id, "chiwar.net"

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
