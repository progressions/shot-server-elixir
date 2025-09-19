# Shot-Elixir Phoenix API Gap Analysis

## Executive Summary

The Phoenix API (`shot-elixir`) is making solid progress toward Rails parity, with **264/264 tests passing** and core CRUD operations implemented. However, **critical gaps remain** in file storage (ImageKit) and real-time features (WebSockets) that are essential for production use.

## Current Implementation Status

### ✅ Completed (100% Functional)
- **Authentication**: JWT via Guardian, compatible with Devise
- **Core CRUD Controllers**: All 11 main resource controllers implemented
  - Campaigns (30 tests)
  - Characters (19 tests)
  - Vehicles (18 tests)
  - Weapons (20 tests)
  - Schticks (22 tests)
  - Fights & Shots
  - Sites (18 tests)
  - Parties (18 tests)
  - Factions (17 tests)
  - Junctures (17 tests)
- **Database Integration**: Successfully using Rails PostgreSQL database
- **Test Coverage**: 264/264 tests passing

### ❌ Critical Missing Features

#### 1. **ImageKit File Storage** (ESSENTIAL)
Rails implementation has:
- Active Storage with ImageKit integration
- `WithImagekit` concern for image URL generation
- ImageKit CDN URLs with caching
- Image position tracking for UI features

Phoenix currently has:
- **NO file upload implementation**
- **NO ImageKit integration**
- **NO Active Storage equivalent**
- Image fields exist in schemas but are non-functional

**Required Work:**
- Implement Arc or Waffle for file uploads
- Add ImageKit API integration
- Create image URL generation service
- Add caching layer for CDN URLs
- Implement image position management

#### 2. **WebSocket/Phoenix Channels** (ESSENTIAL)
Rails implementation has:
- `CampaignChannel` - Real-time campaign updates
- `FightChannel` - Fight state synchronization with user presence
- Redis-backed user presence tracking
- Real-time broadcasts after state changes

Phoenix currently has:
- **NO Phoenix Channels implemented**
- **NO WebSocket endpoint configured**
- **NO real-time update broadcasting**
- Controllers exist but don't broadcast changes

**Required Work:**
- Create UserSocket with Guardian authentication
- Implement CampaignChannel module
- Implement FightChannel with presence tracking
- Add Redis integration for presence
- Add broadcast calls to all controllers after mutations
- Configure WebSocket endpoint in router

### ⚠️ Partially Implemented Features

#### 3. **Background Jobs**
Rails has Sidekiq with:
- AI character/image generation
- Notion synchronization
- Discord notifications
- Campaign broadcasts

Phoenix has:
- **NO background job processing**
- **NO Oban setup**
- Controllers for AI endpoints exist but are synchronous

#### 4. **External Service Integrations**
Rails has:
- OpenAI integration for AI features
- Notion API for character sync
- Discord bot commands
- ImageKit for CDN

Phoenix has:
- **NO external service integrations**
- Endpoint stubs exist but aren't functional

#### 5. **Advanced Features**
Missing in Phoenix:
- PDF generation for character sheets
- Email notifications (invitations)
- Discord bot integration
- Notion sync capabilities
- Character image generation
- Rate limiting for API endpoints

## Implementation Priority & Effort Estimates

### Phase 1: Critical Infrastructure (1-2 weeks)

#### ImageKit Integration (5-7 days)
```elixir
# Required packages
{:arc, "~> 0.11"}
{:arc_s3, "~> 0.4"}
{:imagekit, "~> 0.1"} # or custom client

# Implementation tasks:
1. Configure Arc for file uploads (1 day)
2. Build ImageKit service module (1 day)
3. Update character/vehicle schemas (1 day)
4. Add upload endpoints to controllers (1 day)
5. Implement caching layer (1 day)
6. Testing & debugging (1-2 days)
```

#### Phoenix Channels (3-5 days)
```elixir
# Implementation tasks:
1. Configure UserSocket with auth (0.5 day)
2. Create CampaignChannel module (1 day)
3. Create FightChannel with presence (1 day)
4. Add broadcasts to controllers (1 day)
5. Redis integration for presence (0.5 day)
6. Testing with frontend (1-2 days)
```

### Phase 2: Background Processing (3-5 days)
```elixir
# Required packages
{:oban, "~> 2.17"}

# Workers needed:
- AiCharacterWorker
- AiImageWorker
- NotionSyncWorker
- DiscordNotificationWorker
```

### Phase 3: External Services (1 week)
- OpenAI API client
- Notion API integration
- Discord bot setup
- Email service (SendGrid/Mailgun)

## Risk Assessment

### 🔴 **High Risk Items**
1. **No file uploads = No character images** - Core feature broken
2. **No WebSockets = No real-time updates** - Degraded UX
3. **No background jobs = Synchronous AI calls** - Performance issues

### 🟡 **Medium Risk Items**
- Missing rate limiting could allow API abuse
- No email notifications affects invitation flow
- PDF generation missing impacts character exports

### 🟢 **Low Risk Items**
- Discord integration (nice-to-have)
- Notion sync (optional feature)

## Database & Schema Alignment

Good news: Schemas largely match Rails models
Issues found:
- Some JSONB fields need proper Ecto embedding
- Timestamp field naming (inserted_at vs created_at)
- Missing some Rails-specific columns

## Minimum Viable Parity Checklist

For the Phoenix API to be production-ready:

- [ ] **ImageKit file uploads working**
- [ ] **Phoenix Channels broadcasting**
- [ ] **Character image URLs generating correctly**
- [ ] **Real-time fight updates**
- [ ] **Background job processing (Oban)**
- [ ] **AI character generation**
- [ ] **Email invitations**
- [ ] **Rate limiting**
- [ ] **Error tracking (Sentry/Rollbar)**
- [ ] **Performance monitoring**

## Recommended Next Steps

1. **URGENT**: Implement ImageKit integration (blocks core functionality)
2. **URGENT**: Set up Phoenix Channels (required for real-time features)
3. **HIGH**: Add Oban for background jobs
4. **HIGH**: Integrate OpenAI for AI features
5. **MEDIUM**: Add email service for invitations
6. **LOW**: Complete remaining integrations

## Time to Production Parity

**Optimistic estimate**: 3-4 weeks with dedicated effort
**Realistic estimate**: 5-6 weeks accounting for testing and debugging
**Conservative estimate**: 8 weeks for full feature parity

## Conclusion

While the Phoenix API has made excellent progress on core CRUD operations and authentication, it's **not yet production-ready** due to missing critical features. The lack of file storage and WebSocket support are showstoppers that must be addressed before the API can serve as a Rails replacement.

The good news: The foundation is solid with 100% test coverage on implemented features. The remaining work is well-defined and achievable.