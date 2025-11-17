# WebSocket Migration: ActionCable to Phoenix Channels

## Problem

The frontend (`shot-client-next`) uses `@rails/actioncable` to connect to WebSocket channels, but the Elixir backend (`shot-elixir`) uses Phoenix Channels, which has a different protocol.

**Error:**
```
WebSocket connection to 'ws://localhost:4002/cable?token=Bearer%20...' failed
```

## Root Cause

ActionCable and Phoenix Channels use different WebSocket protocols:

- **ActionCable** uses a JSON-based protocol with specific message formats
- **Phoenix Channels** uses its own protocol with different message structures

While the Phoenix endpoint includes `"actioncable-v1-json"` as a subprotocol, it doesn't actually implement the ActionCable protocol - it just advertises support for it.

## Solutions

### Option 1: Use Phoenix JavaScript Client (Recommended)

Replace `@rails/actioncable` with the official `phoenix` JavaScript package.

**Benefits:**
- Native Phoenix Channels support
- Better performance
- Actively maintained
- First-class TypeScript support

**Changes Required:**

1. **Install Phoenix client:**
```bash
cd shot-client-next
npm install phoenix
```

2. **Update `websocketClient.ts`:**
```typescript
import { Socket } from "phoenix"

interface ClientDependencies {
  jwt?: string
  api: import("@/lib").Api
}

export function consumer({ jwt, api }: ClientDependencies): Socket {
  const websocketUrl = process.env.NEXT_PUBLIC_WEBSOCKET_URL || "ws://localhost:4002"

  const socket = new Socket(`${websocketUrl}/socket`, {
    params: { token: `Bearer ${jwt}` }
  })

  socket.connect()
  return socket
}
```

3. **Update channel subscriptions** (e.g., in `AppContext.tsx`):

**Before (ActionCable):**
```typescript
const subscription = consumer.subscriptions.create(
  { channel: "CampaignChannel", id: campaignId },
  {
    received: (data) => handleUpdate(data),
    connected: () => console.log("Connected"),
    disconnected: () => console.log("Disconnected")
  }
)
```

**After (Phoenix):**
```typescript
const channel = socket.channel(`campaign:${campaignId}`, {})

channel.on("update", (data) => handleUpdate(data))
channel.on("phx_error", () => console.log("Error"))
channel.on("phx_close", () => console.log("Disconnected"))

channel.join()
  .receive("ok", () => console.log("Connected"))
  .receive("error", (error) => console.log("Connection error:", error))
```

### Option 2: ActionCable Protocol Adapter

Implement an ActionCable protocol adapter in Phoenix.

**Benefits:**
- No frontend changes required
- Backward compatibility with Rails server

**Drawbacks:**
- Complex implementation
- Requires maintaining protocol compatibility
- Performance overhead
- Not a standard solution

**Implementation:** Would require building a custom Phoenix.Socket.Transport that translates ActionCable messages to Phoenix Channel messages.

### Option 3: Keep Rails for WebSockets

Continue using Rails (`shot-server`) for WebSocket connections only.

**Benefits:**
- No changes needed
- Proven to work

**Drawbacks:**
- Requires running both Rails and Elixir servers
- Complexity in deployment
- Split architecture

## Recommendation

**Use Option 1 (Phoenix JavaScript Client)** because:
1. It's the standard approach for Phoenix applications
2. Better long-term maintainability
3. Native protocol support = better performance
4. The frontend code changes are minimal and straightforward
5. Phoenix Channels are designed for Elixir/Phoenix apps

## Implementation Steps

1. Install `phoenix` npm package in `shot-client-next`
2. Create new `phoenixClient.ts` alongside `websocketClient.ts`
3. Update contexts that use WebSocket (mainly `AppContext.tsx`, `EncounterContext.tsx`)
4. Update channel event names to match Phoenix conventions
5. Test all real-time features (campaign updates, fight updates)
6. Remove `@rails/actioncable` dependency once migration is complete

## Channel Event Mapping

| ActionCable          | Phoenix Channels        |
|---------------------|------------------------|
| `channel` param     | Channel topic format   |
| `subscriptions.create` | `socket.channel()`  |
| `received`          | `channel.on("event")` |
| `connected`         | `join().receive("ok")` |
| `disconnected`      | `channel.on("phx_close")` |

## Testing Checklist

- [ ] Campaign channel connection and subscriptions
- [ ] Fight channel updates during combat
- [ ] User channel notifications
- [ ] Reconnection after disconnect
- [ ] Multiple concurrent channel subscriptions
- [ ] Token expiration handling
