defmodule ShotElixirWeb.Api.V2.UserJSON do
  def index(%{data: data}) when is_map(data) do
    # Handle paginated response with metadata
    %{
      users: Enum.map(data.users, &user_json/1),
      meta: data[:meta] || %{},
      is_autocomplete: data[:is_autocomplete] || false
    }
  end

  def index(%{users: users}) when is_list(users) do
    # Handle simple list response
    %{users: Enum.map(users, &user_json/1)}
  end

  def show(%{user: user, token: token}) do
    %{
      user: user_json(user),
      token: token
    }
  end

  def show(%{user: user}) do
    user_json(user)
  end

  def current(%{user: user}) do
    user_json_with_campaigns(user)
  end

  def profile(%{user: user}) do
    user_json_with_campaigns(user)
  end

  def error(%{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  defp user_json(user) do
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

  defp user_json_with_campaigns(user) do
    base = user_json(user)

    campaigns =
      case Map.get(user, :campaigns) do
        %Ecto.Association.NotLoaded{} -> []
        campaigns -> Enum.map(campaigns, &campaign_summary/1)
      end

    player_campaigns =
      case Map.get(user, :player_campaigns) do
        %Ecto.Association.NotLoaded{} -> []
        campaigns -> Enum.map(campaigns, &campaign_summary/1)
      end

    Map.merge(base, %{
      campaigns: campaigns,
      player_campaigns: player_campaigns
    })
  end

  defp campaign_summary(campaign) do
    %{
      id: campaign.id,
      name: campaign.name,
      description: campaign.description,
      active: campaign.active,
      user_id: campaign.user_id
    }
  end
end
