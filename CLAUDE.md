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
Uses the existing `shot_counter_local` PostgreSQL database with UUID primary keys.

**Local Development:**
- Development: Shares `shot_counter_local` with Rails
- Test: Shares `shot_server_test` with Rails (Rails must set up schema first)

**Test Database Setup:**
The test database schema comes from Rails. For CI environments, use the included schema dump:

```bash
# Set up test database with Rails schema (one-time setup)
# Option 1: Use Mix task (recommended)
mix setup_test_db

# Option 2: Use shell script (for CI)
./setup_ci_db.sh

# Option 3: Manual setup
psql -h localhost -U postgres -d shot_server_test < priv/repo/structure.sql
```

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

## API Response Format Rules

**CRITICAL: Do NOT wrap single-resource responses in a root key.**

The API follows Rails Active Model Serializers conventions where single resources are returned **directly without a wrapper key**.

### show.json Response Format

**CORRECT - Return data directly:**
```elixir
def render("show.json", %{character: character}) do
  render_character_full(character)  # Returns %{id: ..., name: ..., ...}
end
```

**WRONG - Do NOT wrap in a key:**
```elixir
def render("show.json", %{character: character}) do
  %{character: render_character_full(character)}  # WRONG!
end
```

### Current View Patterns

| Resource | show.json | index.json |
|----------|-----------|------------|
| character | direct | `%{characters: [...], meta: ...}` |
| vehicle | direct | `%{vehicles: [...], meta: ...}` |
| weapon | direct | `%{weapons: [...], meta: ...}` |
| schtick | direct | `%{schticks: [...], meta: ...}` |
| site | direct | `%{sites: [...], meta: ...}` |
| party | direct | `%{parties: [...], meta: ...}` |
| faction | direct | `%{factions: [...], meta: ...}` |
| juncture | direct | `%{junctures: [...], meta: ...}` |
| invitation | direct | `%{invitations: [...]}` |
| user | direct | N/A |
| encounter | direct | N/A |
| campaign | direct | `%{campaigns: [...], meta: ...}` |
| fight | direct | `%{fights: [...], meta: ...}` |

### Composite Responses (Multiple Objects)

When returning multiple distinct objects, wrap each in its key:

```elixir
# set_current returns both campaign and user - wrap both
def render("set_current.json", %{campaign: campaign, user: user}) do
  %{
    campaign: render_campaign_detail(campaign),
    user: render_user_full(user)
  }
end
```

### Test Assertions

When testing show/create/update endpoints, access response fields directly:

```elixir
# CORRECT
response = json_response(conn, 200)
assert response["id"] == character.id
assert response["name"] == "Test Character"

# WRONG - character is not wrapped
assert response["character"]["id"] == character.id
```

For index endpoints, use the plural key:
```elixir
response = json_response(conn, 200)
assert length(response["characters"]) == 2
```

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

## CircleCI Setup

For CircleCI, add this to your `.circleci/config.yml`:

```yaml
- run:
    name: Setup test database
    command: |
      cd shot-elixir
      ./setup_ci_db.sh

- run:
    name: Run Elixir tests
    command: |
      cd shot-elixir
      mix test
```

The `priv/repo/structure.sql` file contains the complete Rails schema and should be committed to version control.

## Email System

Shot Elixir uses **Swoosh** for email delivery with **Oban** for background job processing.

### Email Configuration

**Development:**
- Uses `Swoosh.Adapters.Local` for email preview in browser
- Emails are not actually sent, but can be viewed in the mailbox preview
- Access preview at: `http://localhost:4002/dev/mailbox` (when configured)

**Test:**
- Uses `Swoosh.Adapters.Test` for email assertions
- Oban runs in `:inline` mode (no background processing)
- Use `Swoosh.TestAssertions` to verify emails in tests

**Production:**
- Uses `Swoosh.Adapters.SMTP` with Office 365
- Emails queued via Oban `:emails` queue with 3 retry attempts
- Requires `SMTP_USERNAME` and `SMTP_PASSWORD` environment variables

### Email Types Implemented

**User Emails (from admin@chiwar.net):**
1. **Invitation Email** - Campaign invitations with acceptance link
2. **Welcome Email** - Greeting for new users
3. **Joined Campaign** - Notification when user joins a campaign
4. **Removed from Campaign** - Notification when user is removed
5. **Confirmation Instructions** - Account confirmation (template ready, needs token infrastructure)
6. **Password Reset** - Password reset link (template ready, needs reset flow)

**Admin Emails (from system@chiwar.net):**
1. **Blob Sequence Error** - Critical system error notifications

### Sending Emails

Emails are queued via Oban workers for background delivery:

```elixir
# Queue an invitation email
%{"type" => "invitation", "invitation_id" => invitation.id}
|> ShotElixir.Workers.EmailWorker.new()
|> Oban.insert()

# Queue a campaign membership email
%{"type" => "joined_campaign", "user_id" => user.id, "campaign_id" => campaign.id}
|> ShotElixir.Workers.EmailWorker.new()
|> Oban.insert()
```

### Email Templates

Templates are located in `lib/shot_elixir_web/templates/email/`:
- `user_email/*.html.heex` - User-facing emails (HTML)
- `user_email/*.text.eex` - User-facing emails (plain text)
- `admin_email/*.html.heex` - Admin emails (HTML)
- `admin_email/*.text.eex` - Admin emails (plain text)

Templates use inline CSS for email client compatibility and match the Rails email designs.

### Email Modules

**Core Modules:**
- `ShotElixir.Mailer` - Base Swoosh mailer
- `ShotElixir.Emails.UserEmail` - User-facing email builder
- `ShotElixir.Emails.AdminEmail` - Admin email builder
- `ShotElixir.Workers.EmailWorker` - Oban background worker
- `ShotElixirWeb.EmailView` - Template view helpers

### Production Setup

Set SMTP credentials as Fly.io secrets:

```bash
fly secrets set SMTP_USERNAME=admin@chiwar.net -a shot-elixir
fly secrets set SMTP_PASSWORD=<password> -a shot-elixir
```

### Monitoring Email Delivery

Oban provides job monitoring. Failed emails are automatically retried up to 3 times with exponential backoff.

Check Oban job status:
```elixir
# In IEx console
ShotElixir.Repo.all(Oban.Job) |> Enum.filter(&(&1.queue == "emails"))
```

### Email Preview in Development

To enable email preview in development, add this route to your router:

```elixir
if Mix.env() == :dev do
  scope "/dev" do
    pipe_through :browser
    forward "/mailbox", Plug.Swoosh.MailboxPreview
  end
end
```

Then access `http://localhost:4002/dev/mailbox` to view sent emails.

### Automatic Email Triggers

Emails are automatically sent when:
- ✅ **Invitation created** → Invitation email sent
- ✅ **Invitation resent** → Invitation email sent
- ✅ **User joins campaign** → Joined campaign email sent
- ✅ **User removed from campaign** → Removed from campaign email sent
- 📝 **User registers** → Confirmation email (needs token implementation)
- 📝 **Password reset requested** → Reset email (needs reset flow)

## Migration Path

1. Phoenix API runs alongside Rails API
2. Frontend can switch between APIs via config
3. Gradual endpoint migration
4. Full cutover when all endpoints implemented