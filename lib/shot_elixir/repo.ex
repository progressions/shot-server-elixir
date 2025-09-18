defmodule ShotElixir.Repo do
  use Ecto.Repo,
    otp_app: :shot_elixir,
    adapter: Ecto.Adapters.Postgres
end
