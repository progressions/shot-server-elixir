# CLAUDE.md - Shot Elixir Phoenix API

This Phoenix API replicates the Rails shot-server API endpoints using the same PostgreSQL database.

## Project Overview

This is a Phoenix 1.8 API application that provides identical endpoints to the Rails shot-server, sharing the same database (shot_counter_local). It's designed to be a drop-in replacement for the Rails API with full compatibility.

## Architecture

### Core Technologies
- **Phoenix 1.8** - Web framework
- **PostgreSQL** - Shared database with Rails app
- **Guardian** - JWT authentication (Devise equivalent)
- **Bcrypt** - Password hashing
- **CORS Plug** - Cross-origin request handling
- **Phoenix Channels** - WebSocket support (Action Cable equivalent)

### Database
Uses the existing `shot_counter_local` PostgreSQL database with UUID primary keys. No migrations needed - works with existing Rails schema.

### API Structure
Implements Rails API V2 endpoints under `/api/v2/`:
- RESTful JSON API
- JWT token authentication
- Identical request/response formats to Rails

## Development Commands

```bash
# Install dependencies
mix deps.get

# Start Phoenix server (port 4002)
mix phx.server

# Interactive console
iex -S mix phx.server

# Run tests
mix test

# Format code
mix format

# Check compilation warnings
mix compile --warning-as-errors
```

## API Endpoints (V2 Implementation)

All endpoints mirror Rails `/api/v2/*` structure:

### Authentication
- `POST /users/sign_in` - Login (returns JWT)
- `POST /users/sign_up` - Registration
- `DELETE /users/sign_out` - Logout

### Core Resources
- `/api/v2/campaigns` - Campaign management
- `/api/v2/characters` - Character CRUD
- `/api/v2/vehicles` - Vehicle management
- `/api/v2/fights` - Combat encounters
- `/api/v2/shots` - Initiative tracking
- `/api/v2/weapons` - Equipment
- `/api/v2/schticks` - Character abilities
- `/api/v2/sites` - Locations
- `/api/v2/parties` - Groups
- `/api/v2/factions` - Organizations
- `/api/v2/junctures` - Time periods
- `/api/v2/users` - User management
- `/api/v2/invitations` - Campaign invitations
- `/api/v2/encounters` - Combat/chase encounters
- `/api/v2/ai` - AI character generation
- `/api/v2/ai_images` - AI image generation

### WebSocket Channels
Phoenix Channels replicate Action Cable functionality:
- `CampaignChannel` - Campaign-wide updates
- `FightChannel` - Fight-specific updates

## Schema Mapping

Phoenix schemas map directly to Rails Active Record models:
- Uses existing database tables
- UUID primary keys
- Same associations and validations
- Compatible JSON serialization

## Authentication

Guardian JWT tokens compatible with Devise JWT:
- Same token format and claims
- Authorization header: `Bearer <token>`
- Shared secret key configuration

## Development Notes

- Port 4002 to avoid conflict with Rails (3000) and Next.js (3001)
- Shared database means both APIs can run simultaneously
- JSON responses match Rails serializer format
- Same CORS configuration for frontend compatibility

## Testing

```bash
# Test with existing frontend
curl -X POST http://localhost:4002/users/sign_in \
  -H "Content-Type: application/json" \
  -d '{"user":{"email":"progressions@gmail.com","password":"password"}}'
```

## Migration Path

1. Phoenix API runs alongside Rails API
2. Frontend can switch between APIs via config
3. Gradual endpoint migration
4. Full cutover when all endpoints implemented