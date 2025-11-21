defmodule ShotElixir.Mailer do
  @moduledoc """
  The main mailer module for Shot Elixir.

  Uses Swoosh for email delivery. Configured with different adapters
  per environment:
  - Development: Swoosh.Adapters.Local (preview in browser)
  - Test: Swoosh.Adapters.Test
  - Production: Swoosh.Adapters.SMTP (Office 365)
  """
  use Swoosh.Mailer, otp_app: :shot_elixir
end
