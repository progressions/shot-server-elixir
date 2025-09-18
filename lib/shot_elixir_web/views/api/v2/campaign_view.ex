defmodule ShotElixirWeb.Api.V2.CampaignView do
  def render("index.json", %{campaigns: data}) do
    # Handle both old format (list) and new format (map with meta)
    case data do
      %{campaigns: campaigns, meta: meta, is_autocomplete: is_autocomplete} ->
        campaign_serializer =
          if is_autocomplete, do: &render_campaign_autocomplete/1, else: &render_campaign/1

        %{
          campaigns: Enum.map(campaigns, campaign_serializer),
          meta: meta
        }

      %{campaigns: campaigns, meta: meta} ->
        %{
          campaigns: Enum.map(campaigns, &render_campaign/1),
          meta: meta
        }

      campaigns when is_list(campaigns) ->
        # Legacy format for backward compatibility
        %{
          campaigns: Enum.map(campaigns, &render_campaign/1),
          meta: %{
            current_page: 1,
            per_page: 15,
            total_count: length(campaigns),
            total_pages: 1
          }
        }
    end
  end

  def render("show.json", %{campaign: campaign}) do
    %{campaign: render_campaign_detail(campaign)}
  end

  def render("set_current.json", %{campaign: campaign, user: user}) do
    %{
      campaign: render_campaign(campaign),
      user: %{
        id: user.id,
        current_campaign_id: user.current_campaign_id
      }
    }
  end

  def render("current_fight.json", %{campaign: campaign, fight: fight}) do
    %{
      campaign: render_campaign(campaign),
      current_fight: if(fight, do: render_fight(fight), else: nil)
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

  defp render_campaign(campaign) do
    %{
      id: campaign.id,
      name: campaign.name,
      description: campaign.description,
      active: campaign.active,
      is_master_template: campaign.is_master_template,
      user_id: campaign.user_id,
      created_at: campaign.created_at,
      updated_at: campaign.updated_at
    }
  end

  defp render_campaign_autocomplete(campaign) do
    %{
      id: campaign.id,
      name: campaign.name,
      active: campaign.active
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
    %{
      id: character.id,
      name: character.name,
      archetype: character.archetype,
      character_type: character.character_type
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
end
