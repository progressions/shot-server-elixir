defmodule ShotElixirWeb.Api.V2.PlayerViewTokenView do
  @moduledoc """
  View for rendering PlayerViewToken JSON responses.
  """

  def render("index.json", %{tokens: tokens, frontend_url: frontend_url}) do
    %{
      tokens:
        Enum.map(tokens, fn token ->
          %{
            id: token.id,
            token: token.token,
            url: "#{frontend_url}/magic-link/#{token.token}",
            expires_at: DateTime.to_iso8601(token.expires_at),
            fight_id: token.fight_id,
            character_id: token.character_id,
            user_id: token.user_id
          }
        end)
    }
  end

  def render("show.json", %{token: token, frontend_url: frontend_url}) do
    %{
      id: token.id,
      token: token.token,
      url: "#{frontend_url}/magic-link/#{token.token}",
      expires_at: DateTime.to_iso8601(token.expires_at),
      fight_id: token.fight_id,
      character_id: token.character_id,
      user_id: token.user_id
    }
  end

  def render("redeem.json", %{
        jwt: jwt,
        user: user,
        encounter_id: encounter_id,
        character_id: character_id,
        redirect_url: redirect_url
      }) do
    %{
      jwt: jwt,
      user: user,
      encounter_id: encounter_id,
      character_id: character_id,
      redirect_url: redirect_url
    }
  end
end
