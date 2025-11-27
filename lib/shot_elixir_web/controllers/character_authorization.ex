defmodule ShotElixirWeb.CharacterAuthorization do
  @moduledoc """
  Shared authorization logic for character-related controllers.
  """

  alias ShotElixir.Campaigns

  @doc """
  Authorizes read access to a character.
  Returns :ok if the user can view the character, otherwise {:error, :not_found}.
  """
  def authorize_character_access(character, user) do
    campaign = Campaigns.get_campaign(character.campaign_id)

    cond do
      campaign.user_id == user.id -> :ok
      user.admin -> :ok
      user.gamemaster && Campaigns.is_member?(campaign.id, user.id) -> :ok
      Campaigns.is_member?(campaign.id, user.id) && character.user_id == user.id -> :ok
      Campaigns.is_member?(campaign.id, user.id) -> :ok
      true -> {:error, :not_found}
    end
  end

  @doc """
  Authorizes edit access to a character.
  Returns :ok if the user can edit the character, {:error, :forbidden} if they can view but not edit,
  or {:error, :not_found} if they cannot access the character at all.
  """
  def authorize_character_edit(character, user) do
    campaign = Campaigns.get_campaign(character.campaign_id)

    cond do
      campaign.user_id == user.id -> :ok
      user.admin -> :ok
      user.gamemaster && Campaigns.is_member?(campaign.id, user.id) -> :ok
      character.user_id == user.id && Campaigns.is_member?(campaign.id, user.id) -> :ok
      Campaigns.is_member?(campaign.id, user.id) -> {:error, :forbidden}
      true -> {:error, :not_found}
    end
  end
end
