defmodule ShotElixir.BroadcastManager do
  @moduledoc """
  GenServer that manages broadcasting entity changes to WebSocket clients
  in a Rails ActionCable-compatible format.
  """
  use GenServer
  require Logger

  alias ShotElixirWeb.Api.V2.{
    CharacterView,
    VehicleView,
    FightView,
    SiteView,
    PartyView,
    FactionView,
    JunctureView,
    UserView
  }

  defstruct broadcast_count: 0,
            last_broadcast: nil,
            error_count: 0

  # Client API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %__MODULE__{}, name: __MODULE__)
  end

  @doc """
  Broadcasts an entity change to all connected clients on the campaign channel.
  """
  def broadcast_entity_change(entity, action) when action in [:insert, :update, :delete] do
    GenServer.cast(__MODULE__, {:broadcast, entity, action})
  end

  @doc """
  Gets the current health status of the broadcast manager.
  """
  def health_check do
    GenServer.call(__MODULE__, :health)
  end

  # Server Callbacks

  @impl true
  def init(state) do
    Logger.info("BroadcastManager started")
    {:ok, state}
  end

  @impl true
  def handle_cast({:broadcast, entity, action}, state) do
    Task.start(fn ->
      try do
        perform_broadcast(entity, action)
      rescue
        error ->
          Logger.error("Broadcast failed: #{inspect(error)}")
          Logger.error(Exception.format_stacktrace())
      end
    end)

    new_state = %{
      state
      | broadcast_count: state.broadcast_count + 1,
        last_broadcast: DateTime.utc_now()
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:health, _from, state) do
    health = %{
      status: if(state.error_count < 5, do: :healthy, else: :degraded),
      broadcast_count: state.broadcast_count,
      last_broadcast: state.last_broadcast,
      error_count: state.error_count
    }

    {:reply, health, state}
  end

  # Private Functions

  defp perform_broadcast(entity, action) when action in [:insert, :update] do
    entity_type = get_entity_type(entity)
    campaign_id = get_campaign_id(entity)

    if campaign_id do
      # Clear image cache if applicable
      clear_image_cache_if_needed(entity, entity_type)

      # Load associations if needed
      entity_with_associations = preload_associations(entity, entity_type)

      # Serialize entity using appropriate view
      serialized =
        entity_with_associations
        |> serialize_entity(entity_type)
        |> stringify_keys()

      # Broadcast entity update (Rails format)
      Phoenix.PubSub.broadcast!(
        ShotElixir.PubSub,
        "campaign:#{campaign_id}",
        {:rails_message, %{entity_type => serialized}}
      )

      # Broadcast reload signal (Rails format)
      Phoenix.PubSub.broadcast!(
        ShotElixir.PubSub,
        "campaign:#{campaign_id}",
        {:rails_message, %{"#{entity_type}s" => "reload"}}
      )

      Logger.info(
        "Broadcasted #{action} for #{entity_type} #{entity.id} to campaign:#{campaign_id}"
      )

      emit_telemetry(entity_type, action)
    else
      Logger.warning("Cannot broadcast #{entity_type} without campaign_id")
    end
  end

  defp perform_broadcast(entity, :delete) do
    entity_type = get_entity_type(entity)
    campaign_id = get_campaign_id(entity)

    if campaign_id do
      # Only broadcast reload on delete
      Phoenix.PubSub.broadcast!(
        ShotElixir.PubSub,
        "campaign:#{campaign_id}",
        {:rails_message, %{"#{entity_type}s" => "reload"}}
      )

      Logger.info("Broadcasted delete reload for #{entity_type}s to campaign:#{campaign_id}")
      emit_telemetry(entity_type, :delete)
    end
  end

  defp get_entity_type(entity) do
    entity.__struct__
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp get_campaign_id(entity) do
    case get_entity_type(entity) do
      "campaign" -> Map.get(entity, :id)
      # Users don't have campaign_id
      "user" -> nil
      _ -> Map.get(entity, :campaign_id)
    end
  end

  defp clear_image_cache_if_needed(entity, entity_type) do
    if Map.has_key?(entity, :image) || Map.has_key?(entity, :image_url) do
      cache_key = "#{entity_type}:#{entity.id}:image_url"
      Cachex.del(:image_cache, cache_key)
      Logger.debug("Cleared image cache for #{cache_key}")
    end
  end

  defp preload_associations(entity, _entity_type) do
    # For now, return entity as-is
    # In the future, we can preload associations here if needed
    entity
  end

  defp serialize_entity(entity, "character") do
    # Ensure we have the minimal structure for the view
    character = ensure_associations(entity, [:user, :faction, :juncture, :image_positions])

    CharacterView.render("show.json", %{character: character})
    |> Map.get(:character)
  end

  defp serialize_entity(entity, "vehicle") do
    vehicle = ensure_associations(entity, [:user, :campaign, :image_positions])

    VehicleView.render("show.json", %{vehicle: vehicle})
    |> Map.get(:vehicle)
  end

  defp serialize_entity(entity, "fight") do
    fight = ensure_associations(entity, [:campaign, :shots])

    FightView.render("show.json", %{fight: fight})
    |> Map.get(:fight)
  end

  defp serialize_entity(entity, "weapon") do
    weapon = ensure_associations(entity, [:campaign, :juncture])

    %{
      id: weapon.id,
      name: weapon.name,
      damage: weapon.damage,
      concealment: weapon.concealment,
      reload_value: weapon.reload_value,
      category: weapon.category,
      juncture_id: Map.get(weapon, :juncture_id),
      juncture: Map.get(weapon, :juncture),
      campaign_id: weapon.campaign_id,
      entity_class: "Weapon",
      created_at: weapon.created_at,
      updated_at: weapon.updated_at
    }
  end

  defp serialize_entity(entity, "schtick") do
    %{
      id: entity.id,
      name: entity.name,
      category: entity.category,
      description: entity.description,
      campaign_id: entity.campaign_id,
      entity_class: "Schtick",
      created_at: entity.created_at,
      updated_at: entity.updated_at
    }
  end

  defp serialize_entity(entity, "site") do
    site = ensure_associations(entity, [:campaign])

    SiteView.render("show.json", %{site: site})
    |> Map.get(:site)
  end

  defp serialize_entity(entity, "party") do
    party = ensure_associations(entity, [:campaign])

    PartyView.render("show.json", %{party: party})
    |> Map.get(:party)
  end

  defp serialize_entity(entity, "faction") do
    faction = ensure_associations(entity, [:campaign])

    FactionView.render("show.json", %{faction: faction})
    |> Map.get(:faction)
  end

  defp serialize_entity(entity, "juncture") do
    juncture = ensure_associations(entity, [:campaign])

    JunctureView.render("show.json", %{juncture: juncture})
    |> Map.get(:juncture)
  end

  defp serialize_entity(entity, "user") do
    user = ensure_associations(entity, [])

    UserView.render("show.json", %{user: user})
    |> Map.get(:user)
  end

  defp serialize_entity(entity, "campaign") do
    %{
      id: entity.id,
      name: entity.name,
      description: entity.description,
      entity_class: "Campaign",
      created_at: entity.created_at,
      updated_at: entity.updated_at
    }
  end

  defp serialize_entity(entity, entity_type) do
    # Fallback for unknown entity types
    Logger.warning("Unknown entity type for serialization: #{entity_type}")

    %{
      id: entity.id,
      entity_class: String.capitalize(entity_type)
    }
  end

  defp ensure_associations(entity, associations) do
    # Ensure associations are not NotLoaded
    Enum.reduce(associations, entity, fn assoc, acc ->
      case Map.get(acc, assoc) do
        %Ecto.Association.NotLoaded{} ->
          Map.put(acc, assoc, nil)

        _ ->
          acc
      end
    end)
  end

  defp emit_telemetry(entity_type, action) do
    :telemetry.execute(
      [:shot_elixir, :broadcast, :sent],
      %{count: 1},
      %{entity_type: entity_type, action: action}
    )
  end

  defp stringify_keys(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp stringify_keys(%NaiveDateTime{} = datetime), do: NaiveDateTime.to_iso8601(datetime)
  defp stringify_keys(%Time{} = time), do: Time.to_iso8601(time)

  defp stringify_keys(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> stringify_keys()
  end

  defp stringify_keys(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, val}, acc ->
      Map.put(acc, stringify_key(key), stringify_keys(val))
    end)
  end

  defp stringify_keys(value) when is_list(value) do
    Enum.map(value, &stringify_keys/1)
  end

  defp stringify_keys(value), do: value

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key), do: to_string(key)
end
