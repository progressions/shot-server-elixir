defmodule ShotElixirWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.
  Used for tracking users in fights and campaigns in real-time.
  """

  use Phoenix.Presence,
    otp_app: :shot_elixir,
    pubsub_server: ShotElixir.PubSub
end