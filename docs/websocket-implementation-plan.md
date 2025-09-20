# WebSocket Implementation Plan for Rails ActionCable Compatibility

## Overview

This document outlines the implementation strategy to make the Elixir Phoenix backend's WebSocket functionality exactly compatible with the Rails ActionCable behavior, allowing the Next.js frontend to connect without any modifications.

## Current State Analysis

### Rails ActionCable Implementation
- **Endpoint**: `/cable`
- **Authentication**: JWT token in query params
- **Channels**: `CampaignChannel`, `FightChannel`, `UserChannel`
- **Broadcasting Pattern**:
  - Automatic broadcasts via `Broadcastable` concern
  - Background jobs (Sidekiq) for async processing
  - Two-message pattern: entity update + reload signal
  - Payload format: `{"entity_name": serialized_data}` and `{"entity_names": "reload"}`

### Elixir Phoenix Current Implementation
- **Endpoint**: `/cable` (configured in endpoint.ex)
- **Authentication**: JWT token handling (compatible)
- **Channels**: Already implemented
- **Missing**: Automatic model-level broadcasts
- **Missing**: Exact payload format matching

## Implementation Strategy

### Phase 1: GenServer Broadcasting System

#### 1.1 Create BroadcastManager GenServer

```elixir
# lib/shot_elixir/broadcast_manager.ex
defmodule ShotElixir.BroadcastManager do
  use GenServer
  require Logger

  # Client API
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def broadcast_entity_change(entity, action) do
    GenServer.cast(__MODULE__, {:broadcast, entity, action})
  end

  # Server Callbacks
  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_cast({:broadcast, entity, action}, state) do
    Task.start(fn ->
      perform_broadcast(entity, action)
    end)
    {:noreply, state}
  end

  defp perform_broadcast(entity, action) when action in [:insert, :update] do
    entity_type = get_entity_type(entity)
    campaign_id = get_campaign_id(entity)

    # Clear image cache if applicable
    clear_image_cache_if_needed(entity)

    # Serialize entity using appropriate view
    serialized = serialize_entity(entity, entity_type)

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
  end

  defp perform_broadcast(entity, :delete) do
    entity_type = get_entity_type(entity)
    campaign_id = get_campaign_id(entity)

    # Only broadcast reload on delete
    Phoenix.PubSub.broadcast!(
      ShotElixir.PubSub,
      "campaign:#{campaign_id}",
      {:rails_message, %{"#{entity_type}s" => "reload"}}
    )
  end

  defp get_entity_type(entity) do
    entity.__struct__
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp get_campaign_id(entity) do
    Map.get(entity, :campaign_id)
  end

  defp clear_image_cache_if_needed(entity) do
    if Map.has_key?(entity, :image) do
      # Clear Cachex image cache
      Cachex.del(:image_cache, "#{get_entity_type(entity)}:#{entity.id}")
    end
  end

  defp serialize_entity(entity, "character") do
    ShotElixirWeb.Api.V2.CharacterView.render_character_full(entity)
  end

  defp serialize_entity(entity, "vehicle") do
    ShotElixirWeb.Api.V2.VehicleView.render_vehicle_full(entity)
  end

  defp serialize_entity(entity, "fight") do
    ShotElixirWeb.Api.V2.FightView.render_fight_full(entity)
  end

  # Add more serializers as needed...
end
```

#### 1.2 Add to Application Supervision Tree

```elixir
# lib/shot_elixir/application.ex
children = [
  # ... existing children ...
  ShotElixir.BroadcastManager,
  # ... rest ...
]
```

### Phase 2: Broadcastable Behavior Module

#### 2.1 Create Broadcastable Module

```elixir
# lib/shot_elixir/models/broadcastable.ex
defmodule ShotElixir.Models.Broadcastable do
  @moduledoc """
  Provides automatic broadcasting for model changes via Phoenix.PubSub.
  Mimics Rails Broadcastable concern behavior.
  """

  defmacro __using__(_opts) do
    quote do
      import ShotElixir.Models.Broadcastable

      def broadcast_after_commit(%Ecto.Changeset{} = changeset) do
        case changeset.action do
          :insert ->
            broadcast_change(changeset.data, :insert)
          :update ->
            broadcast_change(changeset.data, :update)
          :delete ->
            broadcast_change(changeset.data, :delete)
          _ ->
            :ok
        end
        {:ok, changeset}
      end

      defp broadcast_change(entity, action) do
        # Use GenServer for consistent broadcasting
        ShotElixir.BroadcastManager.broadcast_entity_change(entity, action)
      end

      defoverridable broadcast_after_commit: 1
    end
  end
end
```

### Phase 3: Update Campaign Channel

#### 3.1 Modify CampaignChannel for Rails Compatibility

```elixir
# lib/shot_elixir_web/channels/campaign_channel.ex
defmodule ShotElixirWeb.CampaignChannel do
  use ShotElixirWeb, :channel
  alias ShotElixir.Campaigns

  @impl true
  def join("campaign:" <> campaign_id, _payload, socket) do
    user = socket.assigns.user

    case authorize_campaign_access(campaign_id, user) do
      :ok ->
        # Subscribe to PubSub for this campaign
        Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign_id}")

        socket = assign(socket, :campaign_id, campaign_id)
        {:ok, %{status: "ok"}, socket}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  # Handle Rails-compatible broadcast messages
  @impl true
  def handle_info({:rails_message, payload}, socket) do
    # Push to client without event name (Rails ActionCable format)
    # The client expects messages without specific event names
    push(socket, "message", payload)
    {:noreply, socket}
  end

  # Existing authorization logic...
  defp authorize_campaign_access(campaign_id, user) do
    # ... existing code ...
  end
end
```

### Phase 4: Context Module Integration

#### 4.1 Update Context Modules to Use Broadcasting

```elixir
# lib/shot_elixir/characters.ex
defmodule ShotElixir.Characters do
  alias ShotElixir.Repo
  alias ShotElixir.Characters.Character
  alias Ecto.Multi

  def create_character(attrs \\ %{}) do
    Multi.new()
    |> Multi.insert(:character, Character.changeset(%Character{}, attrs))
    |> Multi.run(:broadcast, fn _repo, %{character: character} ->
      ShotElixir.BroadcastManager.broadcast_entity_change(character, :insert)
      {:ok, character}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, :character, changeset, _} -> {:error, changeset}
    end
  end

  def update_character(%Character{} = character, attrs) do
    Multi.new()
    |> Multi.update(:character, Character.changeset(character, attrs))
    |> Multi.run(:broadcast, fn _repo, %{character: character} ->
      ShotElixir.BroadcastManager.broadcast_entity_change(character, :update)
      {:ok, character}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, :character, changeset, _} -> {:error, changeset}
    end
  end

  def delete_character(%Character{} = character) do
    Multi.new()
    |> Multi.delete(:character, character)
    |> Multi.run(:broadcast, fn _repo, %{character: character} ->
      ShotElixir.BroadcastManager.broadcast_entity_change(character, :delete)
      {:ok, character}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{character: character}} -> {:ok, character}
      {:error, :character, changeset, _} -> {:error, changeset}
    end
  end
end
```

### Phase 5: WebSocket Connection Handling

#### 5.1 Ensure Proper WebSocket Upgrade

The `/cable` endpoint is already configured in `endpoint.ex`:
```elixir
socket "/cable", ShotElixirWeb.UserSocket,
  websocket: true,
  longpoll: false
```

The client connection issue appears to be related to WebSocket upgrade headers. The frontend should be connecting with proper WebSocket protocol, not HTTP GET.

### Phase 6: Testing Strategy

#### 6.1 Connection Testing
```javascript
// Frontend connection test
const cable = ActionCable.createConsumer('ws://localhost:4002/cable')
const subscription = cable.subscriptions.create(
  { channel: "CampaignChannel", id: campaignId },
  {
    received(data) {
      console.log('Received:', data)
    }
  }
)
```

#### 6.2 Broadcast Testing
```elixir
# Elixir console test
character = Characters.get_character!(character_id)
ShotElixir.BroadcastManager.broadcast_entity_change(character, :update)
# Should see message in frontend console
```

## Key Implementation Details

### Message Format Compatibility
Rails ActionCable sends messages without specific event names. The Elixir implementation must:
1. Use generic "message" event for all broadcasts
2. Include entity type as root key in payload
3. Send both entity data and reload signals

### Serialization Matching
All serialized entities must include:
- `entity_class` field (e.g., "Character", "Vehicle")
- Exact same field names as Rails serializers
- Same nested structure for associations

### Background Processing
While Rails uses Sidekiq, Elixir uses:
- GenServer for state management
- Task.start for async execution
- Phoenix.PubSub for message distribution

## Advantages of Elixir Approach

1. **Lower Latency**: No job queue overhead
2. **Fault Tolerance**: Supervisor restarts on failures
3. **Scalability**: PubSub works across nodes
4. **Simplicity**: No external dependencies (Redis/Sidekiq)
5. **Real-time**: Leverages BEAM's concurrency model

## Migration Checklist

- [ ] Implement BroadcastManager GenServer
- [ ] Create Broadcastable module
- [ ] Update all context modules
- [ ] Modify channels for Rails compatibility
- [ ] Test with frontend
- [ ] Verify message format matches
- [ ] Ensure all entity types covered
- [ ] Performance testing
- [ ] Deploy and monitor

## Monitoring and Debugging

### Logging
```elixir
# Add to BroadcastManager
Logger.info("Broadcasting #{action} for #{entity_type} #{entity.id}")
```

### Telemetry
```elixir
:telemetry.execute(
  [:shot_elixir, :broadcast],
  %{count: 1},
  %{entity_type: entity_type, action: action}
)
```

## Future Enhancements

1. **Batch Broadcasting**: Group multiple updates
2. **Selective Broadcasting**: Filter by user permissions
3. **Compression**: For large payloads
4. **Rate Limiting**: Prevent broadcast storms
5. **Analytics**: Track real-time usage patterns