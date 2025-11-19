defmodule ShotElixir.Models.Broadcastable do
  @moduledoc """
  Provides automatic broadcasting for model changes via Phoenix.PubSub.
  Mimics Rails Broadcastable concern behavior for ActionCable compatibility.
  """

  defmacro __using__(_opts) do
    quote do
      import ShotElixir.Models.Broadcastable

      @doc """
      Broadcasts entity changes after database commits.
      Should be called from context modules after successful operations.
      """
      def broadcast_after_commit(%Ecto.Changeset{} = changeset, action) do
        broadcast_change(changeset.data, action)
        {:ok, changeset}
      end

      def broadcast_after_commit(entity, action) do
        broadcast_change(entity, action)
        {:ok, entity}
      end

      @doc """
      Broadcasts an entity change via Phoenix.PubSub.
      """
      def broadcast_change(entity, action) when action in [:insert, :update, :delete] do
        entity_name = entity.__struct__ |> Module.split() |> List.last() |> String.downcase()

        topic =
          case entity_name do
            "campaign" -> "campaign:#{entity.id}"
            _ ->
              # Safely get campaign_id, handle case where it might not exist
              case Map.get(entity, :campaign_id) do
                nil -> "campaign:unknown"  # Fallback for entities without campaign_id
                campaign_id -> "campaign:#{campaign_id}"
              end
          end

        # Use proper serialization with view system
        serialized_entity =
          case entity_name do
            "character" ->
              ShotElixirWeb.Api.V2.CharacterView.render("show.json", %{character: entity})

            "weapon" ->
              ShotElixirWeb.Api.V2.WeaponView.render("show.json", %{weapon: entity})

            "schtick" ->
              ShotElixirWeb.Api.V2.SchticksView.render("show.json", %{schtick: entity})

            "site" ->
              ShotElixirWeb.Api.V2.SiteView.render("show.json", %{site: entity})

            "vehicle" ->
              ShotElixirWeb.Api.V2.VehicleView.render("show.json", %{vehicle: entity})

            "party" ->
              ShotElixirWeb.Api.V2.PartyView.render("show.json", %{party: entity})

            "faction" ->
              ShotElixirWeb.Api.V2.FactionView.render("show.json", %{faction: entity})

            "juncture" ->
              ShotElixirWeb.Api.V2.JunctureView.render("show.json", %{juncture: entity})

            "fight" ->
              ShotElixirWeb.Api.V2.FightView.render("show.json", %{fight: entity})

            "campaign" ->
              ShotElixirWeb.Api.V2.CampaignView.render("show.json", %{campaign: entity})
          end

        Phoenix.PubSub.broadcast(
          ShotElixir.PubSub,
          topic,
          {:rails_message, %{entity_name => serialized_entity}}
        )
      end

      @doc """
      Helper to broadcast successful repo operations while preserving the tuple interface.

      Optionally accepts a transform function that can preload or mutate the entity prior
      to broadcasting and returning it.
      """
      def broadcast_result(result, action, transform \\ & &1)

      def broadcast_result({:ok, entity}, action, transform)
          when action in [:insert, :update, :delete] and is_function(transform, 1) do
        entity = transform.(entity)
        broadcast_change(entity, action)
        {:ok, entity}
      end

      def broadcast_result(result, _action, _transform), do: result

      defoverridable broadcast_after_commit: 2, broadcast_change: 2, broadcast_result: 3
    end
  end

  @doc """
  Helper function to broadcast changes for entities that don't use the macro.
  """
  def broadcast(entity, action) when action in [:insert, :update, :delete] do
    entity_name = entity.__struct__ |> Module.split() |> List.last() |> String.downcase()

    topic =
      case entity_name do
        "campaign" -> "campaign:#{entity.id}"
        _ ->
          # Safely get campaign_id, handle case where it might not exist
          case Map.get(entity, :campaign_id) do
            nil -> "campaign:unknown"  # Fallback for entities without campaign_id
            campaign_id -> "campaign:#{campaign_id}"
          end
      end

    # Use proper serialization with view system
    serialized_entity =
      case entity_name do
        "character" ->
          ShotElixirWeb.Api.V2.CharacterView.render("show.json", %{character: entity})

        "weapon" ->
          ShotElixirWeb.Api.V2.WeaponView.render("show.json", %{weapon: entity})

        "schtick" ->
          ShotElixirWeb.Api.V2.SchticksView.render("show.json", %{schtick: entity})

        "site" ->
          ShotElixirWeb.Api.V2.SiteView.render("show.json", %{site: entity})

        "vehicle" ->
          ShotElixirWeb.Api.V2.VehicleView.render("show.json", %{vehicle: entity})

        "party" ->
          ShotElixirWeb.Api.V2.PartyView.render("show.json", %{party: entity})

        "faction" ->
          ShotElixirWeb.Api.V2.FactionView.render("show.json", %{faction: entity})

        "juncture" ->
          ShotElixirWeb.Api.V2.JunctureView.render("show.json", %{juncture: entity})

        "fight" ->
          ShotElixirWeb.Api.V2.FightView.render("show.json", %{fight: entity})

        "campaign" ->
          ShotElixirWeb.Api.V2.CampaignView.render("show.json", %{campaign: entity})
      end

    Phoenix.PubSub.broadcast(
      ShotElixir.PubSub,
      topic,
      {:rails_message, %{entity_name => serialized_entity}}
    )
  end
end
