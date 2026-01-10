defmodule ShotElixirWeb.EmailView do
  @moduledoc """
  View helpers for email templates.

  Provides utility functions for building URLs, formatting dates,
  and rendering email content.
  """

  use Phoenix.View,
    root: "lib/shot_elixir_web/templates",
    namespace: ShotElixirWeb,
    pattern: "**/*"

  import Phoenix.HTML, only: [raw: 1]

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

  @doc """
  Renders email content wrapped in the shared layout template.

  The layout provides a consistent branded header and footer with
  dark theme styling and amber accents matching the Chi War app.

  ## Parameters
    - template: The template path to render (e.g., "user_email/welcome.html")
    - assigns: Map of assigns to pass to the template

  ## Options (via assigns)
    - :email_title - Title for the email (appears in `<title>` tag)
    - :recipient_email - Email address shown in footer

  ## Example

      render_with_layout("user_email/welcome.html", %{
        user: user,
        email_title: "Welcome to Chi War",
        recipient_email: user.email
      })
  """
  def render_with_layout(template, assigns) do
    # Render the inner content template
    inner_content = Phoenix.View.render_to_string(__MODULE__, template, assigns)

    # Wrap in layout with inner_content available
    layout_assigns = Map.put(assigns, :inner_content, inner_content)
    Phoenix.View.render_to_string(__MODULE__, "_layout.html", layout_assigns)
  end

  @doc """
  Renders a styled button for use in emails.

  ## Parameters
    - url: The URL the button links to
    - text: The button text
    - opts: Optional keyword list with :style option

  ## Styles
    - :primary (default) - Amber/gold button
    - :secondary - Grey button
    - :danger - Red button

  ## Example

      render_button("https://chiwar.net/confirm", "Confirm Account")
      render_button("https://chiwar.net/reset", "Reset Password", style: :danger)
  """
  def render_button(url, text, opts \\ []) do
    style = Keyword.get(opts, :style, :primary)
    Phoenix.View.render_to_string(__MODULE__, "_button.html", %{url: url, text: text, style: style})
  end
end
