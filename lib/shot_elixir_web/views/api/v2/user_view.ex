defmodule ShotElixirWeb.Api.V2.UserView do

  def render("index.json", %{users: users}) do
    %{users: Enum.map(users, &render_user/1)}
  end

  def render("show.json", %{user: user, token: token}) do
    %{
      user: render_user(user),
      token: token
    }
  end

  def render("show.json", %{user: user}) do
    %{user: render_user(user)}
  end

  def render("current.json", %{user: user}) do
    render_user_with_campaigns(user)
  end

  def render("profile.json", %{user: user}) do
    render_user_with_campaigns(user)
  end

  defp render_user(user) do
    %{
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      name: user.name,
      admin: user.admin,
      gamemaster: user.gamemaster,
      current_campaign_id: user.current_campaign_id,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  defp render_user_with_campaigns(user) do
    base = render_user(user)

    campaigns = case Map.get(user, :campaigns) do
      %Ecto.Association.NotLoaded{} -> []
      campaigns -> Enum.map(campaigns, &render_campaign_summary/1)
    end

    player_campaigns = case Map.get(user, :player_campaigns) do
      %Ecto.Association.NotLoaded{} -> []
      campaigns -> Enum.map(campaigns, &render_campaign_summary/1)
    end

    Map.merge(base, %{
      campaigns: campaigns,
      player_campaigns: player_campaigns
    })
  end

  defp render_campaign_summary(campaign) do
    %{
      id: campaign.id,
      name: campaign.name,
      description: campaign.description,
      active: campaign.active,
      user_id: campaign.user_id
    }
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    }
  end
end