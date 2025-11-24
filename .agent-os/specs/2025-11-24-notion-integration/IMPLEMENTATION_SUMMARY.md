# Notion Integration Implementation Summary

## Completed ✅

### 1. Investigation & Documentation
- Thoroughly analyzed Rails shot-server Notion integration
- Documented all Notion API behaviors, data mappings, and transformation logic
- Created comprehensive implementation specification

### 2. Database Schema
- ✅ Confirmed `notion_page_id` (UUID) exists in characters table
- ✅ Confirmed `last_synced_to_notion_at` (utc_datetime) exists in characters table
- ✅ Fields already defined in Character schema (lines 66-67)

### 3. HTTP Client
- ✅ Created `lib/shot_elixir/services/notion_client.ex`
- Implements all Notion API v1 operations:
  - search/2 - Search for pages
  - database_query/2 - Query databases with filters
  - create_page/1 - Create new page
  - update_page/2 - Update existing page
  - get_page/1 - Get page by ID
  - get_block_children/1 - Get child blocks
  - append_block_children/2 - Add blocks to page

### 4. Implementation Specification
- ✅ Complete specification document created
- Includes all Character transformation functions
- Exact code for as_notion/1 and attributes_from_notion/2
- All helper functions documented

## Remaining Tasks 📋

### 1. Add Notion Configuration
File: `config/config.exs`

Add at bottom:
```elixir
# Notion API configuration
config :shot_elixir, :notion,
  token: System.get_env("NOTION_TOKEN"),
  database_id: "f6fa27ac-19cd-4b17-b218-55acc6d077be",
  factions_database_id: "0ae94bfa1a754c8fbda28ea50afa5fd5"
```

### 2. Add Character Notion Functions
File: `lib/shot_elixir/characters/character.ex`

Add these functions at the end of the module (complete code in IMPLEMENTATION_SPEC.md):
- `as_notion/1` - Convert character to Notion format
- `attributes_from_notion/2` - Extract from Notion page
- `tags_for_notion/1` - Build tags
- Helper functions: `maybe_add_select/3`, `maybe_add_archetype/2`, `maybe_add_chi_war_link/2`
- HTML stripping: `strip_html/1`
- Property extractors: `get_title/2`, `get_select/2`, `get_number/2`, `get_rich_text/2`
- Value preservation: `av_or_new/3`

### 3. Create NotionService Module
File: `lib/shot_elixir/services/notion_service.ex`

Business logic layer with functions:
- `create_notion_from_character/1`
- `update_notion_from_character/1`
- `sync_character/1` - Main sync function
- `find_or_create_character_from_notion/2`
- `update_character_from_notion/1`
- `find_page_by_name/1`
- `find_faction_by_name/1`
- `find_image_block/1`
- `add_image_to_notion/1`
- `get_description/1`

### 4. Create Oban Worker
File: `lib/shot_elixir/workers/sync_character_to_notion_worker.ex`

```elixir
defmodule ShotElixir.Workers.SyncCharacterToNotionWorker do
  use Oban.Worker, queue: :notion, max_attempts: 3

  alias ShotElixir.Characters
  alias ShotElixir.Services.NotionService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"character_id" => character_id}}) do
    # Only run in production
    if Application.get_env(:shot_elixir, :env) == :prod do
      character = Characters.get_character!(character_id)
      NotionService.sync_character(character)
    end

    :ok
  end
end
```

### 5. Update Character Controller
File: `lib/shot_elixir_web/controllers/api/v2/character_controller.ex`

In `update` action, after successful update:
```elixir
# Queue Notion sync
%{"character_id" => character.id}
|> ShotElixir.Workers.SyncCharacterToNotionWorker.new()
|> Oban.insert()
```

In `duplicate` action, after successful creation:
```elixir
# Queue Notion sync
%{"character_id" => new_character.id}
|> ShotElixir.Workers.SyncCharacterToNotionWorker.new()
|> Oban.insert()
```

### 6. Add Oban Queue Configuration
File: `config/config.exs`

In Oban configuration, add `:notion` queue:
```elixir
config :shot_elixir, Oban,
  # ... existing config
  queues: [
    default: 10,
    emails: 5,
    notion: 3  # Add this line
  ]
```

### 7. Production Environment Variable
Set on Fly.io:
```bash
fly secrets set NOTION_TOKEN=<your-notion-token> -a shot-elixir
```

## Key Implementation Details

### Notion Property Mappings
- **Title**: Character name
- **Select**: Enemy Type, MainAttack, SecondaryAttack, FortuneType
- **Number**: All stat values (Wounds, Defense, Toughness, Speed, Fortune, Guns, Martial Arts, etc.)
- **Rich Text**: Description fields (Age, Height, Weight, Eye/Hair Color, Style of Dress, Melodramatic Hook, Appearance)
- **Checkbox**: Inactive status (!active)
- **Multi-select**: Tags, Faction Tag
- **URL**: Chi War Link (production only)

### Data Transformation Logic
1. **To Notion**: `as_notion/1` builds complete property structure
2. **From Notion**: `attributes_from_notion/2` extracts and merges with existing data
3. **Value Preservation**: Local character values > 7 are preserved over Notion values
4. **HTML Stripping**: Melodramatic Hook and Description strip HTML tags

### Sync Behavior
- Only runs in production environment
- Queued via Oban after character update/duplicate
- Updates `last_synced_to_notion_at` timestamp on success
- Silent failure on errors (matches Rails behavior)

## Testing Considerations

1. Mock Notion API in tests
2. Test character transformation functions independently
3. Test Oban worker with test mode
4. Verify production environment check

## Next Steps

1. Add configuration to config.exs
2. Implement Character Notion functions
3. Create NotionService module
4. Create Oban worker
5. Update character controller
6. Test with mock Notion API
7. Deploy and test in production

## Reference Files

- Rails implementation: `/Users/isaacpriestley/tech/isaacpriestley/chi-war/shot-server/app/services/notion_service.rb`
- Rails Character model: `/Users/isaacpriestley/tech/isaacpriestley/chi-war/shot-server/app/models/character.rb` (lines 190-415)
- Complete spec: `.agent-os/specs/2025-11-24-notion-integration/IMPLEMENTATION_SPEC.md`
