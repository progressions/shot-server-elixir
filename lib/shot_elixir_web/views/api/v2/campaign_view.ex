defmodule ShotElixirWeb.Api.V2.CampaignView do
  alias ShotElixir.AiCredentials

  def render("index.json", %{campaigns: campaigns, meta: meta}) do
    # Batch-load credential checks to avoid N+1 queries
    credential_lookup = build_credential_lookup(campaigns)

    %{
      campaigns: Enum.map(campaigns, &render_campaign(&1, credential_lookup)),
      meta: meta
    }
  end

  def render("show.json", %{campaign: campaign}) do
    render_campaign_detail(campaign)
  end

  def render("current.json", %{campaign: campaign}) do
    render_campaign_detail(campaign)
  end

  def render("set_current.json", %{campaign: campaign, user: user}) do
    %{
      campaign: render_campaign_detail(campaign),
      user: render_user_full(user)
    }
  end

  def render("set_current.json", %{campaign: campaign}) do
    %{
      campaign: render_campaign_detail(campaign),
      user: nil
    }
  end

  def render("current_fight.json", %{fight: fight}) do
    if fight do
      render_fight_detailed(fight)
    else
      nil
    end
  end

  def render("membership.json", %{membership: membership}) do
    %{
      membership: %{
        id: membership.id,
        user_id: membership.user_id,
        campaign_id: membership.campaign_id,
        created_at: membership.created_at
      }
    }
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

  # Build a lookup set of {user_id, provider} pairs that have credentials
  # Used by index.json to avoid N+1 queries
  defp build_credential_lookup(campaigns) do
    pairs =
      campaigns
      |> Enum.filter(& &1.ai_provider)
      |> Enum.map(&{&1.user_id, &1.ai_provider})
      |> Enum.uniq()

    AiCredentials.check_credentials_batch(pairs)
  end

  # Rails CampaignSerializer format - single campaign (may do DB query for credential check)
  defp render_campaign(campaign) do
    render_campaign(campaign, nil)
  end

  # Rails CampaignSerializer format - with optional precomputed credential lookup
  defp render_campaign(campaign, credential_lookup) do
    alias ShotElixir.Campaigns.Campaign

    %{
      id: campaign.id,
      name: campaign.name,
      description: campaign.description,
      user_id: campaign.user_id,
      gamemaster_id: campaign.user_id,
      gamemaster: render_gamemaster_if_loaded(campaign),
      created_at: campaign.created_at,
      updated_at: campaign.updated_at,
      users: render_users_if_loaded(campaign),
      user_ids: get_user_ids(campaign),
      image_url: get_image_url(campaign),
      entity_class: "Campaign",
      active: campaign.active,
      at_a_glance: campaign.at_a_glance,
      image_positions: render_image_positions_if_loaded(campaign),
      # Seeding status fields
      seeding_status: campaign.seeding_status,
      seeding_images_total: campaign.seeding_images_total,
      seeding_images_completed: campaign.seeding_images_completed,
      seeded_at: campaign.seeded_at,
      is_seeding: Campaign.seeding?(campaign),
      is_seeded: Campaign.seeded?(campaign),
      # Batch image generation fields
      batch_image_status: campaign.batch_image_status,
      batch_images_total: campaign.batch_images_total,
      batch_images_completed: campaign.batch_images_completed,
      is_batch_images_in_progress: Campaign.batch_images_in_progress?(campaign),
      # AI credit exhaustion tracking (provider-agnostic)
      ai_credits_exhausted_at: campaign.ai_credits_exhausted_at,
      ai_credits_exhausted_provider: campaign.ai_credits_exhausted_provider,
      is_ai_credits_exhausted: Campaign.ai_credits_exhausted?(campaign),
      # AI generation toggle
      ai_generation_enabled: campaign.ai_generation_enabled,
      # AI provider configuration
      ai_provider: campaign.ai_provider,
      ai_provider_connected: has_ai_provider_credential?(campaign, credential_lookup),
      # Notion Integration
      notion_connected: !!campaign.notion_access_token,
      notion_status: campaign.notion_status || compute_notion_status(campaign),
      notion_workspace_name: campaign.notion_workspace_name,
      notion_workspace_icon: campaign.notion_workspace_icon,
      notion_database_ids: campaign.notion_database_ids || %{},
      notion_oauth_available: notion_oauth_configured?()
    }
  end

  # Check if Notion OAuth credentials are configured in the environment
  defp notion_oauth_configured? do
    client_id = System.get_env("NOTION_CLIENT_ID")
    client_secret = System.get_env("NOTION_CLIENT_SECRET")
    !!(client_id && client_id != "" && client_secret && client_secret != "")
  end

  # Compute notion_status for backwards compatibility with campaigns
  # that don't have the field set yet
  defp compute_notion_status(campaign) do
    if campaign.notion_access_token do
      "working"
    else
      "disconnected"
    end
  end

  # Check if the campaign owner has a credential for the selected AI provider
  # Uses precomputed lookup if available, otherwise queries the database
  defp has_ai_provider_credential?(%{ai_provider: nil}, _credential_lookup), do: false

  defp has_ai_provider_credential?(%{ai_provider: provider, user_id: user_id}, nil) do
    # No lookup provided, fall back to database query
    AiCredentials.has_credential?(user_id, provider)
  end

  defp has_ai_provider_credential?(%{ai_provider: provider, user_id: user_id}, credential_lookup) do
    # Use precomputed lookup to avoid N+1 queries
    MapSet.member?(credential_lookup, {user_id, provider})
  end

  defp render_campaign_detail(campaign) do
    base = render_campaign(campaign)

    # Add associations if they're loaded
    members =
      case Map.get(campaign, :members) do
        %Ecto.Association.NotLoaded{} -> []
        members -> Enum.map(members, &render_user_summary/1)
      end

    characters =
      case Map.get(campaign, :characters) do
        %Ecto.Association.NotLoaded{} -> []
        characters -> Enum.map(characters, &render_character_summary/1)
      end

    fights =
      case Map.get(campaign, :fights) do
        %Ecto.Association.NotLoaded{} -> []
        fights -> Enum.map(fights, &render_fight/1)
      end

    Map.merge(base, %{
      members: members,
      characters: characters,
      fights: fights
    })
  end

  defp render_user_summary(user) do
    %{
      id: user.id,
      email: user.email,
      name: user.name,
      gamemaster: user.gamemaster
    }
  end

  defp render_character_summary(character) do
    action_values = Map.get(character, :action_values) || %{}

    %{
      id: character.id,
      name: character.name,
      archetype: Map.get(action_values, "Archetype"),
      character_type: Map.get(action_values, "Type")
    }
  end

  defp render_fight(fight) do
    %{
      id: fight.id,
      name: fight.name,
      active: fight.active,
      sequence: fight.sequence,
      started_at: fight.started_at,
      ended_at: fight.ended_at,
      created_at: fight.created_at,
      updated_at: fight.updated_at
    }
  end

  defp render_fight_detailed(fight) do
    # Handle potentially loaded or not loaded associations
    characters =
      case Map.get(fight, :characters) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        chars -> Enum.map(chars, &render_character_simple/1)
      end

    vehicles =
      case Map.get(fight, :vehicles) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        vehs -> Enum.map(vehs, &render_vehicle_simple/1)
      end

    character_ids = Enum.map(characters, & &1[:id])
    vehicle_ids = Enum.map(vehicles, & &1[:id])

    %{
      id: fight.id,
      name: fight.name,
      description: fight.description,
      image_url: get_image_url(fight),
      created_at: fight.created_at,
      updated_at: fight.updated_at,
      active: fight.active,
      sequence: fight.sequence,
      characters: characters,
      character_ids: character_ids,
      vehicles: vehicles,
      vehicle_ids: vehicle_ids,
      entity_class: "Fight",
      started_at: fight.started_at,
      ended_at: fight.ended_at,
      season: fight.season,
      session: fight.session,
      campaign_id: fight.campaign_id,
      image_positions: render_image_positions_if_loaded(fight)
    }
  end

  defp render_character_simple(character) do
    %{
      id: character.id,
      name: character.name,
      character_type: get_in(character.action_values, ["Type"]) || "PC",
      user_id: character.user_id,
      image_url: get_image_url(character),
      entity_class: "Character"
    }
  end

  defp render_vehicle_simple(vehicle) do
    %{
      id: vehicle.id,
      name: vehicle.name
    }
  end

  # Helper functions for Rails-compatible associations
  defp render_gamemaster_if_loaded(campaign) do
    case Map.get(campaign, :user) do
      %Ecto.Association.NotLoaded{} -> nil
      nil -> nil
      user -> render_user_full(user)
    end
  end

  defp render_users_if_loaded(campaign) do
    case Map.get(campaign, :members) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      users -> Enum.map(users, &render_user_full/1)
    end
  end

  defp render_image_positions_if_loaded(campaign) do
    case Map.get(campaign, :image_positions) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      positions -> Enum.map(positions, &render_image_position/1)
    end
  end

  defp get_user_ids(campaign) do
    case Map.get(campaign, :members) do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      users -> Enum.map(users, & &1.id)
    end
  end

  # Rails UserSerializer format
  defp render_user_full(user) do
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
      current_campaign_id: Map.get(user, :current_campaign_id),
      created_at: user.created_at,
      updated_at: user.updated_at
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
end
