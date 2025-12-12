defmodule ShotElixir.Encounters do
  @moduledoc """
  The Encounters context - handles player view tokens and encounter-related operations.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Encounters.PlayerViewToken
  alias ShotElixir.Fights.Fight
  alias ShotElixir.Characters.Character

  @doc """
  Creates a player view token for a character in a fight.
  The token allows the character's owner to access the Player View via magic link.

  ## Parameters
    - fight: The Fight struct
    - character: The Character struct (must have user_id)

  ## Returns
    - {:ok, token} on success
    - {:error, changeset} on failure
  """
  def create_player_view_token(%Fight{} = fight, %Character{} = character) do
    attrs = %{
      token: PlayerViewToken.generate_token(),
      expires_at: PlayerViewToken.default_expiry(),
      fight_id: fight.id,
      character_id: character.id,
      user_id: character.user_id
    }

    %PlayerViewToken{}
    |> PlayerViewToken.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a valid (unexpired, unused) token by its string value.

  ## Returns
    - {:ok, token} if found and valid
    - {:error, :not_found} if token doesn't exist
    - {:error, :expired} if token has expired
    - {:error, :already_used} if token was already redeemed
  """
  def get_valid_token(token_string) when is_binary(token_string) do
    case Repo.get_by(PlayerViewToken, token: token_string) do
      nil ->
        {:error, :not_found}

      %PlayerViewToken{used: true} ->
        {:error, :already_used}

      %PlayerViewToken{} = token ->
        if PlayerViewToken.valid?(token) do
          {:ok, Repo.preload(token, [:fight, :character, :user])}
        else
          {:error, :expired}
        end
    end
  end

  @doc """
  Redeems a token, marking it as used.
  Returns the token with preloaded associations for generating the auth response.

  ## Returns
    - {:ok, token} on success (with fight, character, user preloaded)
    - {:error, reason} on failure
  """
  def redeem_token(token_string) when is_binary(token_string) do
    case get_valid_token(token_string) do
      {:ok, token} ->
        token
        |> PlayerViewToken.use_changeset()
        |> Repo.update()

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a token by ID with preloaded associations.
  """
  def get_token(id) do
    PlayerViewToken
    |> Repo.get(id)
    |> Repo.preload([:fight, :character, :user])
  end

  @doc """
  Lists all tokens for a specific fight.
  """
  def list_tokens_for_fight(fight_id) do
    PlayerViewToken
    |> where([t], t.fight_id == ^fight_id)
    |> order_by([t], desc: t.created_at)
    |> Repo.all()
    |> Repo.preload([:character, :user])
  end

  @doc """
  Lists valid (unexpired, unused) tokens for a specific fight.
  Returns one token per character (the most recent valid one).
  """
  def list_valid_tokens_for_fight(fight_id) do
    now = DateTime.utc_now()

    PlayerViewToken
    |> where([t], t.fight_id == ^fight_id)
    |> where([t], t.used == false)
    |> where([t], t.expires_at > ^now)
    |> order_by([t], desc: t.created_at)
    |> Repo.all()
    |> Repo.preload([:character, :user])
    # Group by character and take only the most recent token per character
    |> Enum.group_by(& &1.character_id)
    |> Enum.map(fn {_char_id, tokens} -> List.first(tokens) end)
  end

  @doc """
  Deletes expired tokens. Can be run periodically via Oban job.
  Returns the number of deleted tokens.
  """
  def cleanup_expired_tokens do
    now = DateTime.utc_now()

    {count, _} =
      PlayerViewToken
      |> where([t], t.expires_at < ^now or t.used == true)
      |> Repo.delete_all()

    {:ok, count}
  end

  @doc """
  Checks if a character is in a specific fight (has a shot entry).
  """
  def character_in_fight?(fight_id, character_id) do
    ShotElixir.Fights.Shot
    |> where([s], s.fight_id == ^fight_id and s.character_id == ^character_id)
    |> Repo.exists?()
  end
end
