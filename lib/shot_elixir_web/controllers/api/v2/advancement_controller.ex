defmodule ShotElixirWeb.Api.V2.AdvancementController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Characters
  alias ShotElixir.Characters.Advancement
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/characters/:character_id/advancements
  def index(conn, %{"character_id" => character_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         %{} = _campaign <- Campaigns.get_campaign(character.campaign_id),
         :ok <- authorize_character_access(character, current_user) do
      advancements = Characters.list_advancements(character_id)

      conn
      |> put_view(ShotElixirWeb.Api.V2.AdvancementView)
      |> render("index.json", advancements: advancements)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Character not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to view this character's advancements"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Character not found"})
    end
  end

  # POST /api/v2/characters/:character_id/advancements
  def create(conn, %{"character_id" => character_id, "advancement" => advancement_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         %{} = campaign <- Campaigns.get_campaign(character.campaign_id),
         :ok <- authorize_character_edit(character, current_user),
         {:ok, advancement} <- Characters.create_advancement(character_id, advancement_params) do
      # Broadcast character update (for advancement created) via Phoenix channels
      ShotElixirWeb.Endpoint.broadcast(
        "campaign:#{campaign.id}",
        "character_update",
        %{
          type: "advancement_created",
          character_id: character_id,
          advancement: render_advancement(advancement)
        }
      )

      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.AdvancementView)
      |> render("show.json", advancement: advancement)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Character not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to create advancements for this character"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Character not found"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_changeset_errors(changeset)})
    end
  end

  # GET /api/v2/characters/:character_id/advancements/:id
  def show(conn, %{"character_id" => character_id, "id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         %{} = _campaign <- Campaigns.get_campaign(character.campaign_id),
         :ok <- authorize_character_access(character, current_user),
         %Advancement{} = advancement <- Characters.get_advancement(id),
         :ok <- validate_advancement_belongs_to_character(advancement, character) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.AdvancementView)
      |> render("show.json", advancement: advancement)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Advancement or character not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to view this advancement"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Advancement or character not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Advancement does not belong to this character"})
    end
  end

  # PATCH/PUT /api/v2/characters/:character_id/advancements/:id
  def update(conn, %{
        "character_id" => character_id,
        "id" => id,
        "advancement" => advancement_params
      }) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         %{} = campaign <- Campaigns.get_campaign(character.campaign_id),
         :ok <- authorize_character_edit(character, current_user),
         %Advancement{} = advancement <- Characters.get_advancement(id),
         :ok <- validate_advancement_belongs_to_character(advancement, character),
         {:ok, updated_advancement} <-
           Characters.update_advancement(advancement, advancement_params) do
      # Broadcast character update (for advancement updated) via Phoenix channels
      ShotElixirWeb.Endpoint.broadcast(
        "campaign:#{campaign.id}",
        "character_update",
        %{
          type: "advancement_updated",
          character_id: character_id,
          advancement: render_advancement(updated_advancement)
        }
      )

      conn
      |> put_view(ShotElixirWeb.Api.V2.AdvancementView)
      |> render("show.json", advancement: updated_advancement)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Advancement or character not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to update this advancement"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Advancement or character not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Advancement does not belong to this character"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: format_changeset_errors(changeset)})
    end
  end

  # DELETE /api/v2/characters/:character_id/advancements/:id
  def delete(conn, %{"character_id" => character_id, "id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         %{} = campaign <- Campaigns.get_campaign(character.campaign_id),
         :ok <- authorize_character_edit(character, current_user),
         %Advancement{} = advancement <- Characters.get_advancement(id),
         :ok <- validate_advancement_belongs_to_character(advancement, character),
         {:ok, _advancement} <- Characters.delete_advancement(advancement) do
      # Broadcast character update (for advancement deleted) via Phoenix channels
      ShotElixirWeb.Endpoint.broadcast(
        "campaign:#{campaign.id}",
        "character_update",
        %{
          type: "advancement_deleted",
          character_id: character_id,
          advancement_id: id
        }
      )

      send_resp(conn, :no_content, "")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Advancement or character not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not authorized to delete this advancement"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Advancement or character not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Advancement does not belong to this character"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete advancement"})
    end
  end

  # Private helper functions

  defp validate_advancement_belongs_to_character(advancement, character) do
    if advancement.character_id == character.id do
      :ok
    else
      {:error, :mismatch}
    end
  end

  defp authorize_character_access(character, user) do
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

  defp authorize_character_edit(character, user) do
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

  defp render_advancement(advancement) do
    %{
      id: advancement.id,
      description: advancement.description,
      character_id: advancement.character_id,
      created_at: advancement.created_at,
      updated_at: advancement.updated_at
    }
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
