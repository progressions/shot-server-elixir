defmodule ShotElixirWeb.Api.V2.UserView do
  def render("index.json", %{users: users}) do
    %{
      users: Enum.map(users, &render_user/1)
    }
  end

  def render("show.json", %{user: user}) do
    render_user(user)
  end

  def render("current.json", %{user: user}) do
    render_user_full(user)
  end

  def render("profile.json", %{user: user}) do
    render_user_full(user)
  end

  def render("error.json", %{errors: errors}) do
    %{
      success: false,
      errors: translate_errors(errors)
    }
  end

  def render("error.json", %{error: error}) do
    %{
      success: false,
      errors: %{base: [error]}
    }
  end

  defp render_user(user) do
    %{
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      image_url: get_image_url(user),
      email: user.email,
      name: "#{user.first_name} #{user.last_name}",
      gamemaster: user.gamemaster,
      admin: user.admin,
      entity_class: "User",
      active: user.active,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  defp render_user_full(user) do
    base = render_user(user)

    # Add associations if they're loaded
    image_positions =
      case Map.get(user, :image_positions) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        positions -> Enum.map(positions, &render_image_position/1)
      end

    campaigns =
      case Map.get(user, :campaigns) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        campaigns -> Enum.map(campaigns, &render_campaign_lite/1)
      end

    player_campaigns =
      case Map.get(user, :player_campaigns) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        campaigns -> Enum.map(campaigns, &render_campaign_lite/1)
      end

    onboarding_progress =
      case Map.get(user, :onboarding_progress) do
        %Ecto.Association.NotLoaded{} -> nil
        nil -> nil
        progress -> render_onboarding_progress(progress)
      end

    Map.merge(base, %{
      image_positions: image_positions,
      campaigns: campaigns,
      player_campaigns: player_campaigns,
      onboarding_progress: onboarding_progress
    })
  end

  defp render_image_position(position) do
    %{
      id: position.id,
      context: position.context,
      x_position: position.x_position,
      y_position: position.y_position,
      style_overrides: position.style_overrides
    }
  end

  defp render_campaign_lite(campaign) do
    %{
      id: campaign.id,
      name: campaign.name,
      description: campaign.description,
      active: campaign.active,
      entity_class: "Campaign"
    }
  end

  defp render_onboarding_progress(progress) do
    %{
      id: progress.id,
      user_id: progress.user_id,
      first_campaign_created_at: progress.first_campaign_created_at,
      first_campaign_activated_at: progress.first_campaign_activated_at,
      first_character_created_at: progress.first_character_created_at,
      first_fight_created_at: progress.first_fight_created_at,
      first_faction_created_at: progress.first_faction_created_at,
      first_party_created_at: progress.first_party_created_at,
      first_site_created_at: progress.first_site_created_at,
      congratulations_dismissed_at: progress.congratulations_dismissed_at,
      created_at: progress.created_at,
      updated_at: progress.updated_at,
      entity_class: "OnboardingProgress"
    }
  end

  defp get_image_url(user) do
    ShotElixir.ActiveStorage.get_image_url("User", user.id)
  end

  defp translate_errors(changeset) when is_map(changeset) do
    if Map.has_key?(changeset, :errors) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    else
      changeset
    end
  end

  defp translate_errors(errors), do: errors
end