defmodule ShotElixirWeb.Api.V2.UserView do
  def render("index.json", %{data: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{users: users, meta: meta, is_autocomplete: is_autocomplete} ->
        user_serializer =
          if is_autocomplete, do: &render_user_autocomplete/1, else: &render_user/1

        %{
          users: Enum.map(users, user_serializer),
          meta: meta
        }

      %{users: users, meta: meta} ->
        %{
          users: Enum.map(users, &render_user/1),
          meta: meta
        }

      users when is_list(users) ->
        # Legacy format for backward compatibility
        %{
          users: Enum.map(users, &render_user/1),
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(users),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{user: user, token: token}) do
    %{
      user: render_user_detail(user),
      token: token
    }
  end

  def render("show.json", %{user: user}) do
    %{user: render_user_detail(user)}
  end

  def render("current.json", %{user: user}) do
    %{user: render_user_detail(user)}
  end

  def render("profile.json", %{user: user}) do
    %{user: render_user_detail(user)}
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  # Rails UserSerializer format
  defp render_user(user) do
    %{
      id: user.id,
      first_name: user.first_name,
      last_name: user.last_name,
      image_url: get_image_url(user),
      email: user.email,
      name: "#{user.first_name || ""} #{user.last_name || ""}" |> String.trim(),
      gamemaster: user.gamemaster,
      admin: user.admin,
      entity_class: "User",
      active: user.active,
      created_at: user.created_at,
      updated_at: user.updated_at,
      image_positions: render_image_positions_if_loaded(user),
      campaigns: render_campaigns_if_loaded(user),
      player_campaigns: render_player_campaigns_if_loaded(user),
      onboarding_progress: render_onboarding_progress_if_loaded(user)
    }
  end

  defp render_user_autocomplete(user) do
    %{
      id: user.id,
      name: "#{user.first_name || ""} #{user.last_name || ""}" |> String.trim(),
      entity_class: "User"
    }
  end

  defp render_user_detail(user) do
    base = render_user(user)

    # Add associations if they're loaded
    current_campaign =
      case Map.get(user, :current_campaign) do
        %Ecto.Association.NotLoaded{} -> nil
        campaign -> render_campaign(campaign)
      end

    campaigns =
      case Map.get(user, :campaigns) do
        %Ecto.Association.NotLoaded{} -> []
        campaigns -> Enum.map(campaigns, &render_campaign/1)
      end

    player_campaigns =
      case Map.get(user, :player_campaigns) do
        %Ecto.Association.NotLoaded{} -> []
        campaigns -> Enum.map(campaigns, &render_campaign/1)
      end

    Map.merge(base, %{
      current_campaign: current_campaign,
      campaigns: campaigns,
      player_campaigns: player_campaigns,
      current_campaign_id: user.current_campaign_id
    })
  end

  defp render_campaign(nil), do: nil

  defp render_campaign(campaign) do
    %{
      id: campaign.id,
      name: campaign.name,
      description: campaign.description,
      active: campaign.active,
      user_id: campaign.user_id
    }
  end

  # Helper functions for Rails-compatible associations
  defp render_image_positions_if_loaded(user) do
    case Map.get(user, :image_positions) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      positions -> Enum.map(positions, &render_image_position/1)
    end
  end

  defp render_campaigns_if_loaded(user) do
    case Map.get(user, :campaigns) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      campaigns -> Enum.map(campaigns, &render_campaign_index_lite/1)
    end
  end

  defp render_player_campaigns_if_loaded(user) do
    case Map.get(user, :player_campaigns) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      campaigns -> Enum.map(campaigns, &render_campaign_index_lite/1)
    end
  end

  defp render_onboarding_progress_if_loaded(user) do
    case Map.get(user, :onboarding_progress) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      progress -> render_onboarding_progress(progress)
    end
  end

  # Rails CampaignIndexLiteSerializer format
  defp render_campaign_index_lite(campaign) do
    %{
      id: campaign.id,
      name: campaign.name,
      entity_class: "Campaign"
    }
  end

  # Rails OnboardingProgressSerializer format
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
      updated_at: progress.updated_at
    }
  end

  # Rails ImagePositionSerializer format
  defp render_image_position(position) do
    %{
      id: position.id,
      context: position.context,
      x_position: position.x_position,
      y_position: position.y_position,
      style_overrides: position.style_overrides
    }
  end

  # Rails-compatible image URL handling
  defp get_image_url(record) do
    # TODO: Implement proper image attachment checking
    # For now, return nil like Rails when no image is attached
    Map.get(record, :image_url)
  end
end
