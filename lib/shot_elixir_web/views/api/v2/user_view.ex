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

  defp render_user(user) do
    %{
      id: user.id,
      name: user.name,
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      admin: user.admin,
      gamemaster: user.gamemaster,
      active: user.active,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  defp render_user_autocomplete(user) do
    %{
      id: user.id,
      name: user.name,
      active: user.active
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
end
