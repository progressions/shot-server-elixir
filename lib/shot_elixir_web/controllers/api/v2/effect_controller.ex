defmodule ShotElixirWeb.Api.V2.EffectController do
  @moduledoc """
  Controller for fight-level effects.
  These are effects that apply to the entire fight (e.g., "Building On Fire", "Reinforcements Arriving")
  rather than to individual characters.
  """
  use ShotElixirWeb, :controller

  alias ShotElixir.Fights
  alias ShotElixir.Effects
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian
  alias ShotElixir.Repo
  alias ShotElixirWeb.CampaignChannel

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/fights/:fight_id/effects
  def index(conn, %{"fight_id" => fight_id}) do
    conn = put_view(conn, ShotElixirWeb.Api.V2.EffectView)
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = fight <- Fights.get_fight(fight_id),
         %{} = campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_access(campaign, current_user) do
      effects = Effects.list_effects_for_fight(fight_id)
      render(conn, "index.json", effects: effects)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Not a member of this campaign"})
    end
  end

  # POST /api/v2/fights/:fight_id/effects
  def create(conn, %{"fight_id" => fight_id, "effect" => effect_params}) do
    conn = put_view(conn, ShotElixirWeb.Api.V2.EffectView)
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = fight <- Fights.get_fight(fight_id),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user) do
      # Add fight_id and user_id to params
      effect_params =
        effect_params
        |> Map.put("fight_id", fight_id)
        |> Map.put("user_id", current_user.id)

      case Effects.create_effect(effect_params) do
        {:ok, effect} ->
          # Touch the fight to update timestamp
          Fights.touch_fight(fight)

          # Broadcast encounter update
          broadcast_encounter_update(fight)

          conn
          |> put_status(:created)
          |> render("show.json", effect: effect)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render("error.json", changeset: changeset)
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can create fight effects"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight not found"})
    end
  end

  # PATCH/PUT /api/v2/fights/:fight_id/effects/:id
  def update(conn, %{"fight_id" => fight_id, "id" => id, "effect" => effect_params}) do
    conn = put_view(conn, ShotElixirWeb.Api.V2.EffectView)
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = fight <- Fights.get_fight(fight_id),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user),
         %{} = effect <- Effects.get_effect_for_fight(fight_id, id) do
      case Effects.update_effect(effect, effect_params) do
        {:ok, updated_effect} ->
          # Touch the fight to update timestamp
          Fights.touch_fight(fight)

          # Broadcast encounter update
          broadcast_encounter_update(fight)

          render(conn, "show.json", effect: updated_effect)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render("error.json", changeset: changeset)
      end
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or effect not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can update fight effects"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or effect not found"})
    end
  end

  # DELETE /api/v2/fights/:fight_id/effects/:id
  def delete(conn, %{"fight_id" => fight_id, "id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = fight <- Fights.get_fight(fight_id),
         %{} = _campaign <- Campaigns.get_campaign(fight.campaign_id),
         :ok <- authorize_fight_edit(fight, current_user),
         %{} = effect <- Effects.get_effect_for_fight(fight_id, id),
         {:ok, _deleted} <- Effects.delete_effect(effect) do
      # Touch the fight to update timestamp
      Fights.touch_fight(fight)

      # Broadcast encounter update
      broadcast_encounter_update(fight)

      send_resp(conn, :ok, "")
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or effect not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can delete fight effects"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Fight or effect not found"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to delete effect"})
    end
  end

  # Private helper functions

  defp authorize_fight_access(campaign, user) do
    cond do
      campaign.user_id == user.id -> :ok
      user.admin -> :ok
      Campaigns.is_member?(campaign.id, user.id) -> :ok
      true -> {:error, :forbidden}
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
        :effects,
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
