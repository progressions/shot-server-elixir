defmodule ShotElixirWeb.EmailView do
  @moduledoc """
  View helpers for email templates.

  Provides utility functions for building URLs, formatting dates,
  and rendering email content.
  """

  use Phoenix.View,
    root: "lib/shot_elixir_web/templates",
    namespace: ShotElixirWeb

  @doc """
  Returns the root URL for the frontend application.
  Used to build links in emails.
  """
  def root_url do
    opts = Application.get_env(:shot_elixir, :mailer_url_options, [])
    scheme = opts[:scheme] || "https"
    host = opts[:host] || "chiwar.net"
    port = opts[:port]

    port_string = if port, do: ":#{port}", else: ""
    "#{scheme}://#{host}#{port_string}"
  end

  @doc """
  Formats a DateTime for display in emails.
  """
  def format_timestamp(datetime) when is_struct(datetime, DateTime) do
    Calendar.strftime(datetime, "%B %d, %Y at %I:%M %p UTC")
  end

  def format_timestamp(nil), do: "N/A"

  @doc """
  Returns the current year for copyright notices.
  """
  def current_year do
    DateTime.utc_now().year
  end
end
