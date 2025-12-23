# Shot Elixir

Phoenix/Elixir API backend for [Chi War](https://chiwar.net), a campaign management tool for the Feng Shui 2 tabletop RPG.

## Related Repositories

- **Frontend**: [shot-client-next](https://github.com/progressions/shot-client-next) - Next.js frontend application
- **Parent repo**: [chi-war](https://github.com/progressions/chi-war) - Coordination repository

## Production

- **Backend API**: https://shot-elixir.fly.dev
- **Frontend**: https://chiwar.net

## Requirements

- Elixir 1.15+
- Erlang/OTP 26+
- PostgreSQL 14+
- Node.js (for asset compilation, if needed)

## Setup

### 1. Install Dependencies

```bash
mix deps.get
```

### 2. Database Setup

Create and migrate the database:

```bash
mix ecto.create
mix ecto.migrate
```

### 3. Seed the Database

The seed data includes the Master Campaign template with all schticks, weapons, characters, factions, and junctures needed to create new campaigns:

```bash
mix run priv/repo/seeds.exs
```

This creates:
- A gamemaster user (progressions@gmail.com)
- The Master Campaign (template for new campaigns)
- 643 schticks with images
- 86 weapons with images
- 39 character templates with images
- 12 factions with images
- 7 junctures with images

### 4. Start the Server

```bash
mix phx.server
```

Or with an interactive console:

```bash
iex -S mix phx.server
```

The API runs on [localhost:4002](http://localhost:4002) by default.

## Configuration

### Environment Variables

For local development, defaults are configured in `config/dev.exs`. For production, set these environment variables:

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `SECRET_KEY_BASE` | Phoenix secret key (generate with `mix phx.gen.secret`) |
| `PHX_HOST` | Hostname (e.g., `shot-elixir.fly.dev`) |
| `DISCORD_TOKEN` | Discord bot token (optional) |
| `NOTION_TOKEN` | Notion API key (optional) |
| `IMAGEKIT_PUBLIC_KEY` | ImageKit public key |
| `IMAGEKIT_PRIVATE_KEY` | ImageKit private key |
| `IMAGEKIT_URL_ENDPOINT` | ImageKit URL endpoint |
| `SMTP_USERNAME` | Email username |
| `SMTP_PASSWORD` | Email password |

### Database Port

By default, the app connects to PostgreSQL on port 5432. To use a different port:

```bash
SHOT_ELIXIR_DEV_DB_PORT=5433 mix phx.server
```

## API Endpoints

### Authentication

- `POST /users/sign_in` - Login (returns JWT)
- `POST /users/sign_up` - Registration
- `DELETE /users/sign_out` - Logout

### Resources (under `/api/v2/`)
- `GET /api/v2/campaigns` - List campaigns
- `GET /api/v2/characters` - List characters
- `GET /api/v2/fights` - Combat encounters
- `GET /api/v2/schticks` - Character abilities
- `GET /api/v2/weapons` - Equipment
- `GET /api/v2/factions` - Organizations
- `GET /api/v2/junctures` - Time periods
- `GET /api/v2/sites` - Locations
- `GET /api/v2/parties` - Groups

## Testing

```bash
mix test
```

## Deployment

Deployed to Fly.io:

```bash
fly deploy
```

Monitor logs:

```bash
fly logs
```

## Useful Mix Tasks

```bash
# Export weapon images from production (for updating seeds)
mix export_weapon_images

# Reset database and reseed
mix ecto.reset
mix run priv/repo/seeds.exs
```

## Architecture

- **Phoenix 1.8** - Web framework
- **Ecto** - Database layer with PostgreSQL
- **Guardian** - JWT authentication
- **Oban** - Background job processing
- **Phoenix Channels** - WebSocket support for real-time updates
- **ImageKit** - Image storage and transformation
