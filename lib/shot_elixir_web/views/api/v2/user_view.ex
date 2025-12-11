defmodule ShotElixirWeb.Api.V2.UserView do
  def render("index.json", %{users: users}) do
    %{
      users: Enum.map(users, &render_user/1)
    }
  end

  def render("show.json", %{user: user}) do
    render_user_full(user)
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

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
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
      discord_id: user.discord_id,
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

    # Characters scoped to current campaign (set by controller)
    characters =
      case Map.get(user, :characters) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        chars -> Enum.map(chars, &render_character_lite/1)
      end

    character_ids = Enum.map(characters, & &1.id)

    Map.merge(base, %{
      image_positions: image_positions,
      campaigns: campaigns,
      player_campaigns: player_campaigns,
      onboarding_progress: onboarding_progress,
      characters: characters,
      character_ids: character_ids
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

  defp render_character_lite(character) do
    %{
      id: character.id,
      name: character.name,
      category: get_in(character.action_values, ["Type"]),
      active: character.active,
      image_url: get_image_url(character),
      entity_class: "Character"
    }
  end

  defp render_onboarding_progress(progress) do
    alias ShotElixir.Onboarding.Progress

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
      all_milestones_complete: Progress.all_milestones_complete?(progress),
      onboarding_complete: Progress.onboarding_complete?(progress),
      ready_for_congratulations: Progress.ready_for_congratulations?(progress),
      next_milestone: Progress.next_milestone(progress),
      created_at: progress.created_at,
      updated_at: progress.updated_at,
      entity_class: "OnboardingProgress"
    }
  end

  # Rails-compatible image URL handling
  defp get_image_url(record) when is_map(record) do
    # Check if image_url is already in the record (pre-loaded)
    case Map.get(record, :image_url) do
      nil ->
        # Try to get entity type from struct, fallback to nil if plain map
        entity_type =
          case Map.get(record, :__struct__) do
            # Plain map, skip ActiveStorage lookup
            nil -> nil
            struct_module -> struct_module |> Module.split() |> List.last()
          end

        if entity_type && Map.get(record, :id) do
          ShotElixir.ActiveStorage.get_image_url(entity_type, record.id)
        else
          nil
        end

      url ->
        url
    end
  end

  defp get_image_url(_), do: nil

  defp translate_errors(changeset) when is_map(changeset) do
    if Map.has_key?(changeset, :errors) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          # Handle tuples and other non-string values safely
          value_str =
            case value do
              v when is_binary(v) -> v
              v -> inspect(v)
            end

          String.replace(acc, "%{#{key}}", value_str)
        end)
      end)
    else
      changeset
    end
  end

  defp translate_errors(errors), do: errors
end
