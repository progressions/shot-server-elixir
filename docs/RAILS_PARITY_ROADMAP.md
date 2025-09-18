# Rails API Parity Roadmap

This document outlines the steps needed to achieve full feature parity between the Phoenix `shot-elixir` API and the Rails `shot-server` API.

## Current Status

✅ **Completed:**
- Database configuration (using existing `shot_counter_local`)
- Guardian JWT authentication setup
- Basic User schema and Accounts context
- Authentication controllers (Sessions, Registrations)
- Health check endpoint
- CORS configuration
- Router structure matching Rails V2 API
- ExUnit test setup

⚠️ **In Progress:**
- Domain schemas need completion
- Controllers need implementation
- JSON serialization format matching

## Implementation Phases

### Phase 1: Core Functionality (Week 1-2)

#### 1.1 Complete Domain Schemas

Create Ecto schemas for all Rails models with proper associations:

**Priority Schemas:**
```elixir
# lib/shot_elixir/campaigns/campaign.ex
Campaign
  - name, description, active, is_master_template
  - belongs_to :user
  - has_many :characters
  - has_many :campaign_memberships

# lib/shot_elixir/characters/character.ex
Character
  - name, archetype, character_type, action_values, etc.
  - belongs_to :user, :campaign
  - has_many :schticks, :weapons (through join tables)
  - Full stats: body, chi, mind, reflexes, fortune, etc.

# lib/shot_elixir/fights/fight.ex
Fight
  - name, sequence, shot_counter, fight_type
  - belongs_to :campaign
  - has_many :shots

# lib/shot_elixir/fights/shot.ex
Shot
  - shot_number, acted, hidden
  - belongs_to :fight, :character (or :vehicle)
```

**Secondary Schemas:**
- `Vehicle` - Vehicle stats and combat
- `Weapon` - Equipment with damage/reload/concealment
- `Schtick` - Abilities with prerequisites and categories
- `Site` - Locations with feng shui bonus
- `Faction` - Organizations in the Chi War
- `Party` - Character groupings
- `Juncture` - Time periods (Ancient, 1850s, Contemporary, Future)

**Join Tables:**
- `Attunement` - Character <-> Site
- `Carry` - Character <-> Weapon
- `CharacterSchtick` - Character <-> Schtick
- `PartyMembership` - Party <-> Character/Vehicle

#### 1.2 Implement Core Controllers

```elixir
# Priority controllers with their key actions:

UserController
  - index, show, create, update, delete
  - current (GET /api/v2/users/current)
  - profile (GET/PATCH /api/v2/users/profile)

CampaignController
  - CRUD operations
  - set_current (POST /api/v2/campaigns/current)
  - current_fight (GET /api/v2/campaigns/:id/current_fight)

CharacterController
  - CRUD operations
  - autocomplete (GET /api/v2/characters/names)
  - sync (POST /api/v2/characters/:id/sync)
  - duplicate (POST /api/v2/characters/:id/duplicate)
  - import (POST /api/v2/characters/pdf)
```

#### 1.3 JSON Serialization

Create view modules matching Rails ActiveModel Serializers:

```elixir
# lib/shot_elixir_web/views/api/v2/user_view.ex
defmodule ShotElixirWeb.Api.V2.UserView do
  def render("show.json", %{user: user}) do
    %{
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      name: user.name,
      admin: user.admin,
      gamemaster: user.gamemaster,
      current_campaign_id: user.current_campaign_id,
      created_at: user.created_at,
      updated_at: user.updated_at,
      image_url: user.image_url
    }
  end
end
```

### Phase 2: Game Mechanics (Week 2-3)

#### 2.1 Combat System

**Fight Management:**
- Fight creation with shot counter initialization
- Shot tracking (initiative system)
- Character/Vehicle positioning
- Action resolution

**Key Services to Port:**
```elixir
# lib/shot_elixir/combat/dice_roller.ex
DiceRoller
  - roll(positive, negative) - Exploding dice mechanic
  - swerve() - Calculate result swerve

# lib/shot_elixir/combat/encounter_actions.ex
EncounterActions
  - apply_combat_action(fight, actor, action, target)
  - apply_chase_action(fight, vehicle, action)
```

#### 2.2 WebSocket Channels

Implement Phoenix Channels for real-time updates:

```elixir
# lib/shot_elixir_web/channels/campaign_channel.ex
CampaignChannel
  - join("campaign:#{campaign_id}", payload, socket)
  - handle_in("reload", payload, socket)
  - broadcast_update(campaign_id, payload)

# lib/shot_elixir_web/channels/fight_channel.ex
FightChannel
  - join("fight:#{fight_id}", payload, socket)
  - handle_in("shot_update", payload, socket)
  - handle_in("character_action", payload, socket)
```

### Phase 3: Advanced Features (Week 3-4)

#### 3.1 Background Jobs with Oban

Add Oban to `mix.exs`:
```elixir
{:oban, "~> 2.17"}
```

Implement workers:
```elixir
# lib/shot_elixir/workers/ai_character_worker.ex
AiCharacterWorker
  - Generate character descriptions via OpenAI
  - Update character with AI content

# lib/shot_elixir/workers/notion_sync_worker.ex
NotionSyncWorker
  - Sync character to Notion database
  - Update sync status

# lib/shot_elixir/workers/image_processing_worker.ex
ImageProcessingWorker
  - Process uploaded images
  - Generate thumbnails via ImageKit
```

#### 3.2 External Service Integration

**OpenAI Integration:**
```elixir
# lib/shot_elixir/services/ai_service.ex
- Character description generation
- Character name suggestions
- Image generation prompts
```

**Notion API:**
```elixir
# lib/shot_elixir/services/notion_service.ex
- Create/update character pages
- Sync character stats
- Handle Notion webhooks
```

**Discord Bot:**
```elixir
# lib/shot_elixir/services/discord_bot.ex
- Command registration
- Fight management commands
- Character lookup
```

**File Storage (S3/ImageKit):**
```elixir
# Configure Arc or Waffle for S3
{:arc, "~> 0.11"}
{:arc_s3, "~> 0.4"}

# ImageKit CDN integration
# lib/shot_elixir/services/imagekit_service.ex
```

### Phase 4: Polish & Parity (Week 4-5)

#### 4.1 Missing Features

**Authentication Enhancements:**
- Email confirmation (Users::ConfirmationsController)
- Password reset (Users::PasswordsController)
- Account locking after failed attempts
- JWT revocation via JTI tracking

**Invitation System:**
```elixir
# lib/shot_elixir_web/controllers/api/v2/invitation_controller.ex
- create (send invitation email)
- redeem (accept invitation)
- register (create account from invitation)
```

**PDF Generation:**
```elixir
# Add PDF generation library
{:puppeteer_pdf, "~> 1.0"}

# Character sheet PDF generation
# lib/shot_elixir/services/pdf_generator.ex
```

#### 4.2 Performance & Monitoring

**Database Optimization:**
```sql
-- Add indexes for common queries
CREATE INDEX idx_characters_campaign_user ON characters(campaign_id, user_id);
CREATE INDEX idx_shots_fight_character ON shots(fight_id, character_id);
CREATE INDEX idx_campaign_memberships_user ON campaign_memberships(user_id);
```

**Caching Strategy:**
```elixir
# Add Cachex for in-memory caching
{:cachex, "~> 3.6"}

# Cache frequently accessed data
- Current campaign per user
- Active fights
- Character sheets
```

**Monitoring:**
```elixir
# Add telemetry and monitoring
{:telemetry_metrics, "~> 1.0"}
{:telemetry_poller, "~> 1.0"}
```

## Implementation Commands

### Generate Contexts and Schemas

```bash
# Campaign context
mix phx.gen.context Campaigns Campaign campaigns \
  name:string description:text active:boolean \
  is_master_template:boolean user_id:references:users

# Character context
mix phx.gen.context Characters Character characters \
  name:string archetype:string character_type:string \
  campaign_id:references:campaigns user_id:references:users

# Fight context
mix phx.gen.context Fights Fight fights \
  name:string sequence:integer shot_counter:integer \
  campaign_id:references:campaigns

# Generate JSON controllers
mix phx.gen.json Campaigns Campaign campaigns \
  name:string --no-context --no-schema --web Api.V2
```

### Database Migrations

Since we're using the existing Rails database, we don't need migrations for existing tables. However, for Oban:

```bash
mix ecto.gen.migration add_oban_jobs_table
```

```elixir
defmodule ShotElixir.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 11)
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
```

## Testing Strategy

### Unit Tests
- Test all contexts (Accounts, Campaigns, Characters, etc.)
- Test business logic services
- Test view serialization

### Integration Tests
- Test full API request/response cycle
- Test authentication flows
- Test WebSocket channels

### Example Test:
```elixir
# test/shot_elixir_web/controllers/api/v2/character_controller_test.exs
describe "POST /api/v2/characters" do
  test "creates character with valid data", %{conn: conn, user: user} do
    conn = authenticate(conn, user)

    attrs = %{
      name: "Jackie Chan",
      archetype: "Martial Artist",
      character_type: "pc"
    }

    conn = post(conn, "/api/v2/characters", character: attrs)

    assert %{"id" => id} = json_response(conn, 201)
    assert character = Repo.get(Character, id)
    assert character.name == "Jackie Chan"
  end
end
```

## Success Metrics

### Functionality Checklist
- [ ] All V2 API endpoints implemented
- [ ] JWT authentication working
- [ ] WebSocket channels broadcasting
- [ ] Background jobs processing
- [ ] External services integrated
- [ ] PDF generation working
- [ ] Image uploads functional

### Performance Targets
- [ ] API response time < 200ms (p95)
- [ ] WebSocket latency < 50ms
- [ ] Background job processing < 5s
- [ ] Test suite runs < 60s

### Compatibility Goals
- [ ] Frontend can switch between Rails/Phoenix via config
- [ ] Same JWT tokens work on both APIs
- [ ] Database changes compatible with both
- [ ] WebSocket message format identical

## Migration Strategy

1. **Parallel Development**: Keep both APIs running
2. **Feature Flag**: Add API endpoint toggle in frontend
3. **Gradual Migration**: Move endpoints one at a time
4. **Testing**: Extensive testing on staging
5. **Cutover**: Switch production traffic when ready
6. **Rollback Plan**: Keep Rails API available for quick rollback

## Resources

- [Phoenix Documentation](https://hexdocs.pm/phoenix)
- [Ecto Documentation](https://hexdocs.pm/ecto)
- [Guardian JWT](https://hexdocs.pm/guardian)
- [Oban Background Jobs](https://hexdocs.pm/oban)
- [Phoenix Channels Guide](https://hexdocs.pm/phoenix/channels.html)

## Questions & Decisions

### Open Questions
1. Should we maintain Rails serializer format exactly or optimize for Phoenix?
2. How to handle Rails-specific features (e.g., Active Storage)?
3. Migration strategy for background jobs in progress?

### Technical Decisions Made
1. ✅ Use Guardian for JWT (compatible with Devise JWT)
2. ✅ Use existing PostgreSQL database (no migrations needed)
3. ✅ Port 4002 to avoid conflicts
4. ✅ Match Rails JSON format for compatibility

### Pending Decisions
1. ⏳ Background job queue (Oban vs Exq vs Broadway)
2. ⏳ File upload strategy (Arc vs Waffle vs custom)
3. ⏳ Caching layer (Cachex vs Redis vs ETS)

---

*Last Updated: 2025-09-18*
*Status: Phase 0 Complete - Foundation laid, ready for Phase 1 implementation*