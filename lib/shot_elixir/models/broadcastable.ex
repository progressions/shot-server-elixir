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
        # Pass is_gm: true for entities with rich_description_gm_only field
        serialized_entity =
          case entity_name_lower do
            "character" ->
              ShotElixirWeb.Api.V2.CharacterView.render("show.json", %{
                character: entity,
                is_gm: true
              })

            "weapon" ->
              ShotElixirWeb.Api.V2.WeaponView.render("show.json", %{weapon: entity})

            "schtick" ->
              ShotElixirWeb.Api.V2.SchticksView.render("show.json", %{schtick: entity})

            "site" ->
              ShotElixirWeb.Api.V2.SiteView.render("show.json", %{site: entity, is_gm: true})

            "vehicle" ->
              ShotElixirWeb.Api.V2.VehicleView.render("show.json", %{vehicle: entity})

            "party" ->
              ShotElixirWeb.Api.V2.PartyView.render("show.json", %{party: entity, is_gm: true})

            "faction" ->
              ShotElixirWeb.Api.V2.FactionView.render("show.json", %{faction: entity, is_gm: true})

            "juncture" ->
              ShotElixirWeb.Api.V2.JunctureView.render("show.json", %{
                juncture: entity,
                is_gm: true
              })

            "fight" ->
              ShotElixirWeb.Api.V2.FightView.render("show.json", %{fight: entity})

            "adventure" ->
              ShotElixirWeb.Api.V2.AdventureView.render("show.json", %{
                adventure: entity,
                is_gm: true
              })

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

            ShotElixir.Models.Broadcastable.add_encounter_key_if_fight(
              base_payload,
              entity_name_lower,
              entity
            )
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
    # Pass is_gm: true for entities with rich_description_gm_only field
    serialized_entity =
      case entity_name_lower do
        "character" ->
          ShotElixirWeb.Api.V2.CharacterView.render("show.json", %{
            character: entity,
            is_gm: true
          })

        "weapon" ->
          ShotElixirWeb.Api.V2.WeaponView.render("show.json", %{weapon: entity})

        "schtick" ->
          ShotElixirWeb.Api.V2.SchticksView.render("show.json", %{schtick: entity})

        "site" ->
          ShotElixirWeb.Api.V2.SiteView.render("show.json", %{site: entity, is_gm: true})

        "vehicle" ->
          ShotElixirWeb.Api.V2.VehicleView.render("show.json", %{vehicle: entity})

        "party" ->
          ShotElixirWeb.Api.V2.PartyView.render("show.json", %{party: entity, is_gm: true})

        "faction" ->
          ShotElixirWeb.Api.V2.FactionView.render("show.json", %{faction: entity, is_gm: true})

        "juncture" ->
          ShotElixirWeb.Api.V2.JunctureView.render("show.json", %{
            juncture: entity,
            is_gm: true
          })

        "fight" ->
          ShotElixirWeb.Api.V2.FightView.render("show.json", %{fight: entity})

        "adventure" ->
          ShotElixirWeb.Api.V2.AdventureView.render("show.json", %{
            adventure: entity,
            is_gm: true
          })

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
    # For fights, also broadcast as "encounter" for real-time encounter updates
    payload =
      if serialized_entity do
        base_payload = %{
          entity_plural => "reload",
          entity_name_lower => serialized_entity
        }

        ShotElixir.Models.Broadcastable.add_encounter_key_if_fight(
          base_payload,
          entity_name_lower,
          entity
        )
      else
        %{entity_plural => "reload"}
      end

    Phoenix.PubSub.broadcast(
      ShotElixir.PubSub,
      topic,
      {:campaign_broadcast, payload}
    )
  end

  @doc """
  Helper to add "encounter" key for fight broadcasts.
  Ensures shots are preloaded before rendering with EncounterView.
  """
  def add_encounter_key_if_fight(base_payload, entity_name_lower, entity) do
    if entity_name_lower == "fight" do
      # Ensure shots AND their location_ref are preloaded before rendering
      # This is critical for location data to appear in the broadcast
      encounter =
        case Map.get(entity, :shots) do
          %Ecto.Association.NotLoaded{} ->
            Map.put(entity, :shots, [])

          shots when is_list(shots) ->
            # Preload location_ref on shots if not already loaded
            # Check first shot to see if location_ref needs preloading
            needs_preload =
              case shots do
                [] ->
                  false

                [first | _] ->
                  case Map.get(first, :location_ref) do
                    %Ecto.Association.NotLoaded{} -> true
                    _ -> false
                  end
              end

            if needs_preload do
              preloaded_shots =
                ShotElixir.Repo.preload(shots, [
                  :location_ref,
                  :character,
                  :vehicle,
                  :character_effects
                ])

              Map.put(entity, :shots, preloaded_shots)
            else
              entity
            end

          _ ->
            entity
        end

      encounter_data =
        ShotElixirWeb.Api.V2.EncounterView.render("show.json", %{encounter: encounter})

      Map.put(base_payload, "encounter", encounter_data)
    else
      base_payload
    end
  end
end
