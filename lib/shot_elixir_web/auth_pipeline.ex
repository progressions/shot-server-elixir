defmodule ShotElixirWeb.AuthPipeline do
  use Guardian.Plug.Pipeline,
    otp_app: :shot_elixir,
    module: ShotElixir.Guardian,
    error_handler: ShotElixirWeb.AuthErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.LoadResource, allow_blank: true
end
