defmodule ShotElixirWeb.Api.V2.CliAuthView do
  @moduledoc """
  View for rendering CLI authentication responses.
  """

  def render("sessions.json", %{sessions: sessions}) do
    %{cli_sessions: Enum.map(sessions, &render_session/1)}
  end

  defp render_session(session) do
    %{
      id: session.id,
      ip_address: session.ip_address,
      user_agent: session.user_agent,
      last_seen_at: session.last_seen_at,
      created_at: session.inserted_at
    }
  end
end
