defmodule ShotElixirWeb.Api.V2.CampaignView do
  def render("index.json", %{campaigns: campaigns, meta: meta}) do
    %{
      campaigns: Enum.map(campaigns, &render_campaign/1),
      meta: meta
    }
  end

  def render("show.json", %{campaign: campaign}) do
    %{
      campaign: render_campaign_detail(campaign)
    }
  end

  def render("current.json", %{campaign: campaign}) do
    %{
      campaign: render_campaign_detail(campaign)
    }
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

  def render("current_fight.json", %{campaign: campaign, fight: fight}) do
    %{
      campaign: render_campaign(campaign),
      current_fight: if(fight, do: render_fight(fight), else: nil)
    }
  end

  def render("fight_only.json", %{fight: fight}) do
    render_fight_detailed(fight)
  end

  def render("current_fight.json", %{campaign: campaign, fight: fight}) do
    %{
      campaign: render_campaign(campaign),
      current_fight: if(fight, do: render_fight_detailed(fight), else: nil)
    }
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

  # Rails CampaignSerializer format
  defp render_campaign(campaign) do
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
      image_positions: render_image_positions_if_loaded(campaign)
    }
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
      character_type: get_in(character.action_values, ["Type"]) || "PC"
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
