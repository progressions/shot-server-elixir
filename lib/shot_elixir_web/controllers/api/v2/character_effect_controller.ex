defmodule ShotElixirWeb.Api.V2.CharacterEffectController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Effects
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixir.Repo
  alias ShotElixirWeb.CampaignChannel

  action_fallback ShotElixirWeb.FallbackController

  # POST /api/v2/fights/:fight_id/character_effects
  def create(conn, %{"fight_id" => fight_id, "character_effect" => effect_params}) do
    conn = put_view(conn, ShotElixirWeb.Api.V2.CharacterEffectView)
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = fight <- Fights.get_fight(fight_id),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user),
         %{} = shot <- Fights.get_shot(effect_params["shot_id"]),
         :ok <- validate_shot_belongs_to_fight(shot, fight) do
      case Effects.create_character_effect(effect_params) do
        {:ok, character_effect} ->
          # Touch the fight to update timestamp
          Fights.touch_fight(fight)

          # Broadcast encounter update
          broadcast_encounter_update(fight)

          conn
          |> put_status(:created)
          |> render("show.json", character_effect: character_effect)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render("error.json", changeset: changeset)
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or shot not found"})

      {:error, :mismatch} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Shot does not belong to this fight"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can create character effects"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or shot not found"})
    end
  end

  # PATCH/PUT /api/v2/fights/:fight_id/character_effects/:id
  def update(conn, %{"fight_id" => fight_id, "id" => id, "character_effect" => effect_params}) do
    conn = put_view(conn, ShotElixirWeb.Api.V2.CharacterEffectView)
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = fight <- Fights.get_fight(fight_id),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user),
         %{} = character_effect <- Effects.get_character_effect_for_fight(fight_id, id) do
      case Effects.update_character_effect(character_effect, effect_params) do
        {:ok, updated_effect} ->
          # Touch the fight to update timestamp
          Fights.touch_fight(fight)

          # Broadcast encounter update
          broadcast_encounter_update(fight)

          render(conn, "show.json", character_effect: updated_effect)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render("error.json", changeset: changeset)
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or character effect not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can update character effects"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or character effect not found"})
    end
  end

  # DELETE /api/v2/fights/:fight_id/character_effects/:id
  def delete(conn, %{"fight_id" => fight_id, "id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = fight <- Fights.get_fight(fight_id),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user),
         %{} = character_effect <- Effects.get_character_effect_for_fight(fight_id, id),
         {:ok, _deleted} <- Effects.delete_character_effect(character_effect) do
      # Touch the fight to update timestamp
      Fights.touch_fight(fight)

      # Broadcast encounter update
      broadcast_encounter_update(fight)

      send_resp(conn, :ok, "")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or character effect not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can delete character effects"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or character effect not found"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete character effect"})
    end
  end

  # GET /api/v2/fights/:fight_id/character_effects
  def index(conn, %{"fight_id" => fight_id}) do
    conn = put_view(conn, ShotElixirWeb.Api.V2.CharacterEffectView)
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = fight <- Fights.get_fight(fight_id),
         %{} = campaign <- Campaigns.get_campaign(fight.campaign_id),
         true <- Campaigns.is_member?(campaign.id, current_user.id) do
      character_effects = Effects.list_character_effects_for_fight(fight_id)
      render(conn, "index.json", character_effects: character_effects)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not a member of this campaign"})
    end
  end

  # Private helper functions

  defp validate_shot_belongs_to_fight(shot, fight) do
    if shot.fight_id == fight.id do
      :ok
    else
      {:error, :mismatch}
    end
  end

  defp authorize_fight_edit(fight, user) do
    campaign = Campaigns.get_campaign(fight.campaign_id)

    cond do
      campaign.user_id == user.id -> :ok
      user.admin -> :ok
      user.gamemaster && Campaigns.is_member?(campaign.id, user.id) -> :ok
      Campaigns.is_member?(campaign.id, user.id) -> {:error, :forbidden}
      true -> {:error, :not_found}
    end
  end

  defp broadcast_encounter_update(fight) do
    # Get the fight with all associations needed for encounter view
    fight_with_associations =
      Repo.preload(fight, [
        :chase_relationships,
        shots: [
          :character,
          :vehicle,
          :character_effects,
          character: [:faction, :character_schticks, :carries],
          vehicle: [:faction]
        ]
      ])

    CampaignChannel.broadcast_encounter_update(
      fight.campaign_id,
      fight_with_associations
    )
  end
end
