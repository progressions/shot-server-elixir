# Next Steps for Phoenix API Implementation

## Current Status

The Phoenix API replication of the Rails shot-server is progressing well with core functionality implemented:

- ✅ **Authentication**: JWT authentication using Guardian (Devise equivalent)
- ✅ **Campaigns**: Full CRUD with membership management (30 tests passing)
- ✅ **Characters**: Basic CRUD with search/filter (19 tests passing)
- ✅ **Vehicles**: Full CRUD with archetype management (18 tests passing)
- ✅ **Weapons**: Full CRUD with damage/concealment attributes (20 tests passing)
- ✅ **Schticks**: Full CRUD with prerequisite management (22 tests passing)
- ✅ **Fights**: Full CRUD with shot management (implemented)
- ✅ **Shots**: Initiative tracking within fights (implemented)
- ✅ **Database**: Successfully using existing Rails PostgreSQL database
- ✅ **All Tests**: 192/192 tests passing (100% pass rate)

## Immediate Priorities

### 1. ✅ COMPLETED: Fix CharacterController Tests
- Fixed Character schema to match database structure
- Corrected field mappings and JSONB handling
- All character tests now passing

### 2. ✅ COMPLETED: Core Controllers Implementation

#### ✅ FightController and ShotController
- Full CRUD operations for fights
- Shot management (initiative tracking)
- Touch/end fight functionality
- Driver assignment for vehicles
- Proper authorization checks

#### ✅ VehicleController (18 tests passing)
- CRUD operations with soft delete
- Archetype management endpoint
- Integration with fights/chases
- Campaign-scoped queries

#### ✅ WeaponController (20 tests passing)
- Full CRUD with validation
- Damage/concealment attributes
- Category filtering (guns, melee, etc.)
- Juncture support

#### ✅ SchtickController (22 tests passing)
- CRUD with prerequisite management
- Self-referential relationships
- Dependency protection on delete
- Category and path filtering

### 3. Next: Implement Remaining Controllers

#### FactionController & JunctureController
- Simple CRUD for campaign world-building
- Image attachments support

#### SiteController & PartyController
- Location and group management
- Attunement system for sites
- Party membership tracking

## Technical Debt & Improvements

### 1. Schema Alignment
**Problem**: Several schemas don't match the Rails database exactly
**Solution**:
- Audit all schemas against `db/schema.rb`
- Remove non-existent fields
- Add missing fields and associations
- Handle Rails-specific columns (image attachments, etc.)

### 2. Association Management
Many-to-many relationships need proper handling:
- Character ↔ Schtick (via character_schticks)
- Character ↔ Weapon (via carries)
- Character ↔ Party (via memberships)
- Character ↔ Site (via attunements)

### 3. Image Handling
Rails uses Active Storage, Phoenix needs alternative:
- Store image URLs in database
- Consider Arc or Waffle for file uploads
- Or continue using URL-only approach

## Phoenix Channels Implementation

### Priority Channels

#### CampaignChannel
```elixir
- join("campaign:#{campaign_id}")
- handle_in("character_update", payload)
- handle_in("fight_update", payload)
- broadcast character/fight changes
```

#### FightChannel
```elixir
- join("fight:#{fight_id}")
- handle_in("shot_update", payload)
- handle_in("character_act", payload)
- broadcast shot counter changes
- broadcast character actions
```

### Implementation Steps
1. Set up UserSocket with Guardian authentication
2. Create channel modules with authorization
3. Add broadcast calls to controllers after state changes
4. Test with Phoenix channel client

## API Feature Parity Checklist

### Essential Endpoints
- [x] POST /users/sign_in (authentication)
- [x] POST /users (registration)
- [x] DELETE /users/sign_out (logout)
- [x] GET/POST/PATCH/DELETE /api/v2/campaigns
- [x] GET/POST/PATCH/DELETE /api/v2/characters
- [x] GET/POST/PATCH/DELETE /api/v2/fights
- [x] POST/PATCH/DELETE /api/v2/fights/:id/shots
- [x] GET/POST/PATCH/DELETE /api/v2/vehicles
- [x] GET/POST/PATCH/DELETE /api/v2/weapons
- [x] GET/POST/PATCH/DELETE /api/v2/schticks
- [ ] GET/POST/PATCH/DELETE /api/v2/factions
- [ ] GET/POST/PATCH/DELETE /api/v2/junctures
- [ ] GET/POST/PATCH/DELETE /api/v2/sites
- [ ] GET/POST/PATCH/DELETE /api/v2/parties

### Advanced Features
- [ ] Character PDF generation
- [ ] Notion sync integration
- [ ] AI character generation
- [ ] Discord bot integration
- [ ] Image upload/management

## Testing Strategy

### Unit Tests
1. Fix existing Character tests
2. Add tests for each new controller
3. Test authorization logic thoroughly
4. Test complex queries and filters

### Integration Tests
1. Test complete user workflows
2. Test campaign → character → fight flow
3. Test real-time updates via channels
4. Test with actual Rails frontend

### Performance Tests
1. Test with production data volumes
2. Optimize N+1 queries
3. Add database indexes where needed
4. Cache frequently accessed data

## Migration Path

### Phase 1: Feature Parity (Current)
Complete core controllers and fix tests

### Phase 2: Channels & Real-time
Add WebSocket support matching Action Cable

### Phase 3: Frontend Integration
1. Update frontend API client to support both Rails and Phoenix
2. Add environment toggle for API selection
3. Run both APIs in parallel for testing

### Phase 4: Advanced Features
- Background jobs (Oban instead of Sidekiq)
- File uploads
- External integrations (Notion, Discord)

### Phase 5: Production Deployment
1. Deploy Phoenix to staging
2. Run side-by-side with Rails
3. Gradual traffic migration
4. Full cutover when stable

## Development Workflow

### Daily Tasks
1. Run test suite: `mix test`
2. Check compilation: `mix compile --warnings-as-errors`
3. Format code: `mix format`

### Before Commits
1. Ensure all tests pass
2. Update documentation
3. Add/update tests for new features
4. Check for N+1 queries

### Testing Commands
```bash
# Run all tests
mix test

# Run specific test file
mix test test/shot_elixir_web/controllers/api/v2/campaign_controller_test.exs

# Run with coverage
mix test --cover

# Run in watch mode
mix test.watch
```

## Resource Priorities

### Week 1-2
- Fix Character tests
- Implement Fight/Shot/Vehicle controllers
- Basic channel support

### Week 3-4
- Remaining CRUD controllers
- Full channel implementation
- Frontend integration testing

### Week 5-6
- Performance optimization
- Advanced features
- Production preparation

## Known Issues & Workarounds

### Database Constraint Names
Rails uses different constraint names than Phoenix expects.
**Workaround**: Use application-level validations where database constraints fail.

### JSONB Field Handling
Rails serializes JSON automatically, Phoenix needs explicit casting.
**Solution**: Use `embeds_one` or `embeds_many` for nested JSON structures.

### Timestamp Columns
Rails uses `created_at/updated_at`, Phoenix uses `inserted_at/updated_at`.
**Solution**: Configure timestamps in schema with custom names.

## Success Metrics

- [ ] All controller tests passing (100% coverage)
- [ ] Response times < 100ms for standard requests
- [ ] Real-time updates < 50ms latency
- [ ] Frontend fully functional with Phoenix API
- [ ] Zero data inconsistencies vs Rails API

## Questions to Resolve

1. Should we implement file uploads or stay URL-only?
2. How to handle Rails-specific features (Active Storage, Action Cable)?
3. Background job strategy (Oban vs continuing to use Sidekiq)?
4. Deployment strategy (Fly.io, AWS, self-hosted)?
5. Monitoring and error tracking approach?

## Conclusion

The Phoenix API is on track to provide a performant, maintainable replacement for the Rails API. Focus should remain on achieving feature parity before adding Phoenix-specific optimizations. The modular approach allows for incremental migration with minimal risk.