# GenServer Broadcasting Architecture

## Overview

This document describes the GenServer-based broadcasting architecture that provides Rails ActionCable compatibility while following Elixir/OTP best practices.

## Architecture Components

### 1. BroadcastManager GenServer

The central broadcasting coordinator that:
- Handles all entity change broadcasts
- Manages serialization and formatting
- Ensures message compatibility with Rails format
- Provides fault tolerance through OTP supervision

```
┌─────────────────┐
│   Controller    │
└────────┬────────┘
         │ calls
         ▼
┌─────────────────┐
│    Context      │
│   (Characters)  │
└────────┬────────┘
         │ broadcasts via
         ▼
┌─────────────────┐
│ BroadcastManager│
│   (GenServer)   │
└────────┬────────┘
         │ publishes to
         ▼
┌─────────────────┐
│ Phoenix.PubSub  │
└────────┬────────┘
         │ distributes to
         ▼
┌─────────────────┐
│    Channels     │
│  (CampaignChannel)
└────────┬────────┘
         │ pushes to
         ▼
┌─────────────────┐
│  WebSocket      │
│    Clients      │
└─────────────────┘
```

## GenServer Benefits

### 1. State Management
```elixir
defmodule ShotElixir.BroadcastManager do
  use GenServer

  defstruct [
    :broadcast_count,
    :last_broadcast,
    :error_count
  ]

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      broadcast_count: 0,
      last_broadcast: nil,
      error_count: 0
    }
    {:ok, state}
  end
end
```

### 2. Fault Tolerance
The GenServer is supervised and automatically restarted on failure:
```elixir
# In application.ex
children = [
  {ShotElixir.BroadcastManager, restart: :permanent}
]
```

### 3. Async Processing
Broadcasts happen asynchronously without blocking the caller:
```elixir
def broadcast_entity_change(entity, action) do
  GenServer.cast(__MODULE__, {:broadcast, entity, action})
end
```

### 4. Centralized Logic
All broadcasting logic is centralized in one place:
- Serialization strategy
- Message formatting
- Error handling
- Metrics collection

## Implementation Details

### Core Functions

#### 1. Entity Broadcasting
```elixir
@impl true
def handle_cast({:broadcast, entity, action}, state) do
  Task.start(fn ->
    perform_broadcast(entity, action)
  end)

  new_state = %{state |
    broadcast_count: state.broadcast_count + 1,
    last_broadcast: DateTime.utc_now()
  }

  {:noreply, new_state}
end
```

#### 2. Serialization Logic
```elixir
defp serialize_entity(entity, entity_type) do
  case entity_type do
    "character" ->
      ShotElixirWeb.Api.V2.CharacterView.render_character_full(entity)
    "vehicle" ->
      ShotElixirWeb.Api.V2.VehicleView.render_vehicle_full(entity)
    "fight" ->
      ShotElixirWeb.Api.V2.FightView.render_fight_full(entity)
    # ... more entity types
  end
end
```

#### 3. Rails-Compatible Formatting
```elixir
defp format_for_rails(entity_type, serialized_data) do
  %{entity_type => serialized_data}
end

defp format_reload_signal(entity_type) do
  %{"#{entity_type}s" => "reload"}
end
```

## Integration with Phoenix.PubSub

### Publishing Messages
```elixir
Phoenix.PubSub.broadcast!(
  ShotElixir.PubSub,
  "campaign:#{campaign_id}",
  {:rails_message, payload}
)
```

### Channel Subscription
```elixir
# In CampaignChannel
def join("campaign:" <> campaign_id, _payload, socket) do
  Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign_id}")
  {:ok, socket}
end

def handle_info({:rails_message, payload}, socket) do
  push(socket, "message", payload)
  {:noreply, socket}
end
```

## Error Handling

### Graceful Degradation
```elixir
@impl true
def handle_cast({:broadcast, entity, action}, state) do
  try do
    perform_broadcast(entity, action)
    {:noreply, state}
  rescue
    error ->
      Logger.error("Broadcast failed: #{inspect(error)}")
      new_state = %{state | error_count: state.error_count + 1}
      {:noreply, new_state}
  end
end
```

### Circuit Breaker Pattern
```elixir
defp should_broadcast?(state) do
  # Stop broadcasting if too many errors
  state.error_count < 10
end
```

## Monitoring and Telemetry

### Health Check
```elixir
def handle_call(:health, _from, state) do
  health = %{
    status: if(state.error_count < 5, do: :healthy, else: :degraded),
    broadcast_count: state.broadcast_count,
    last_broadcast: state.last_broadcast,
    error_count: state.error_count
  }
  {:reply, health, state}
end
```

### Metrics
```elixir
defp emit_telemetry(entity_type, action) do
  :telemetry.execute(
    [:shot_elixir, :broadcast, :sent],
    %{count: 1},
    %{entity_type: entity_type, action: action}
  )
end
```

## Performance Optimizations

### 1. Task-Based Concurrency
```elixir
Task.start(fn ->
  perform_broadcast(entity, action)
end)
```
Broadcasts run in separate processes, preventing blocking.

### 2. ETS Caching (Optional)
```elixir
# Cache serialized entities briefly
:ets.new(:broadcast_cache, [:set, :public, :named_table])
```

### 3. Batch Broadcasting
```elixir
def handle_cast({:broadcast_batch, entities}, state) do
  Task.start(fn ->
    Enum.each(entities, fn {entity, action} ->
      perform_broadcast(entity, action)
    end)
  end)
  {:noreply, state}
end
```

## Testing Strategy

### Unit Tests
```elixir
test "broadcasts entity update" do
  character = %Character{id: "123", name: "Test"}

  assert :ok = BroadcastManager.broadcast_entity_change(character, :update)

  assert_receive {:rails_message, %{"character" => _data}}
  assert_receive {:rails_message, %{"characters" => "reload"}}
end
```

### Integration Tests
```elixir
test "end-to-end broadcast flow" do
  {:ok, character} = Characters.create_character(%{name: "Test"})

  # Subscribe to campaign channel
  Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{character.campaign_id}")

  # Update character
  {:ok, _updated} = Characters.update_character(character, %{name: "Updated"})

  # Verify broadcasts received
  assert_receive {:rails_message, %{"character" => data}}
  assert data["name"] == "Updated"
end
```

## Comparison with Rails Sidekiq

| Aspect | Rails/Sidekiq | Elixir/GenServer |
|--------|---------------|------------------|
| Job Queue | Redis-backed | In-memory process |
| Persistence | Jobs persisted | No persistence needed |
| Latency | Queue processing delay | Immediate |
| Scaling | Horizontal with Redis | Distributed Erlang |
| Failure Recovery | Job retry logic | OTP supervision |
| Monitoring | Sidekiq Web UI | Observer/Telemetry |

## Best Practices

1. **Always use cast, not call** for broadcasts (fire-and-forget)
2. **Handle errors gracefully** without crashing the GenServer
3. **Monitor health** through telemetry and health checks
4. **Test thoroughly** including failure scenarios
5. **Document entity types** and their serialization requirements

## Future Enhancements

### 1. Priority Broadcasting
```elixir
def handle_cast({:broadcast, entity, action, :high_priority}, state) do
  # Process immediately
end

def handle_cast({:broadcast, entity, action, :low_priority}, state) do
  # Defer or batch
end
```

### 2. Selective Broadcasting
```elixir
defp should_broadcast_to_user?(user_id, entity) do
  # Check permissions
end
```

### 3. Distributed Broadcasting
```elixir
# Broadcast across Elixir nodes
Node.list()
|> Enum.each(fn node ->
  GenServer.cast({__MODULE__, node}, {:broadcast, entity, action})
end)
```

## Troubleshooting

### Common Issues

1. **Messages not received by client**
   - Check PubSub subscription
   - Verify channel join succeeded
   - Confirm message format matches Rails

2. **GenServer crashes**
   - Check logs for error details
   - Verify entity has required fields
   - Ensure serializers handle all cases

3. **High memory usage**
   - Monitor Task spawning rate
   - Consider batching broadcasts
   - Check for memory leaks in serializers

### Debug Mode
```elixir
# Enable verbose logging
config :shot_elixir, :broadcast_debug, true

# In BroadcastManager
if Application.get_env(:shot_elixir, :broadcast_debug) do
  Logger.debug("Broadcasting: #{inspect(payload)}")
end
```