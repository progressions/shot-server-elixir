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
      Sends both reload signal and serialized entity for maximum flexibility.
      """
      def broadcast_change(entity, action) when action in [:insert, :update, :delete] do
        entity_name = entity.__struct__ |> Module.split() |> List.last()
        entity_name_lower = String.downcase(entity_name)

        topic =
          case entity_name_lower do
            "campaign" ->
              "campaign:#{entity.id}"

            _ ->
              # Safely get campaign_id, handle case where it might not exist
              case Map.get(entity, :campaign_id) do
                # Fallback for entities without campaign_id
                nil -> "campaign:unknown"
                campaign_id -> "campaign:#{campaign_id}"
              end
          end

        # Serialize entity using appropriate view
        serialized_entity =
          case entity_name_lower do
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

            "user" ->
              ShotElixirWeb.Api.V2.UserView.render("show.json", %{user: entity})

            _ ->
              nil
          end

        # Get pluralized entity key for reload signal
        entity_plural = pluralize_entity_name(entity_name_lower)

        # Broadcast BOTH reload signal and entity data
        # For fights, also broadcast as "encounter" for real-time encounter updates
        payload =
          if serialized_entity do
            base_payload = %{
              entity_plural => "reload",
              entity_name_lower => serialized_entity
            }

            # Add "encounter" key for fight updates so EncounterContext receives them
            if entity_name_lower == "fight" do
              Map.put(base_payload, "encounter", serialized_entity)
            else
              base_payload
            end
          else
            %{entity_plural => "reload"}
          end

        Phoenix.PubSub.broadcast(
          ShotElixir.PubSub,
          topic,
          {:campaign_broadcast, payload}
        )
      end

      # Simple pluralization helper
      defp pluralize_entity_name(entity_name) do
        case entity_name do
          "party" -> "parties"
          _ -> entity_name <> "s"
        end
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
  Sends both reload signal and serialized entity.
  """
  def broadcast(entity, action) when action in [:insert, :update, :delete] do
    entity_name = entity.__struct__ |> Module.split() |> List.last()
    entity_name_lower = String.downcase(entity_name)

    topic =
      case entity_name_lower do
        "campaign" ->
          "campaign:#{entity.id}"

        _ ->
          case Map.get(entity, :campaign_id) do
            nil -> "campaign:unknown"
            campaign_id -> "campaign:#{campaign_id}"
          end
      end

    # Serialize entity using appropriate view
    serialized_entity =
      case entity_name_lower do
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

        "user" ->
          ShotElixirWeb.Api.V2.UserView.render("show.json", %{user: entity})

        _ ->
          nil
      end

    # Get pluralized entity key
    entity_plural =
      case entity_name_lower do
        "party" -> "parties"
        _ -> entity_name_lower <> "s"
      end

    # Broadcast BOTH reload signal and entity data
    payload =
      if serialized_entity do
        %{
          entity_plural => "reload",
          entity_name_lower => serialized_entity
        }
      else
        %{entity_plural => "reload"}
      end

    Phoenix.PubSub.broadcast(
      ShotElixir.PubSub,
      topic,
      {:campaign_broadcast, payload}
    )
  end
end
