# Copilot Instructions for Shot Elixir

This is a Phoenix 1.8 API application that provides REST API endpoints for a tabletop gaming management system.

## Project Overview

- **Framework**: Phoenix 1.8 with Elixir
- **Database**: PostgreSQL with UUID primary keys
- **Authentication**: Guardian JWT
- **Background Jobs**: Oban
- **Email**: Swoosh with SMTP
- **HTTP Client**: Req (preferred)
- **Discord Integration**: Nostrum

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

# Run precommit checks (compile, format, test)
mix precommit

# Format code
mix format

# Check compilation warnings
mix compile --warnings-as-errors
```

## Code Patterns

### API Response Format

**Single-resource endpoints** return data directly without a wrapper key:

```elixir
# CORRECT
def render("show.json", %{character: character}) do
  render_character_full(character)
end

# WRONG - do NOT wrap
def render("show.json", %{character: character}) do
  %{character: render_character_full(character)}
end
```

**Index endpoints** wrap in plural key with meta:

```elixir
def render("index.json", %{characters: characters, meta: meta}) do
  %{characters: Enum.map(characters, &render_character/1), meta: meta}
end
```

### HTTP Requests

Use the `:req` (`Req`) library for HTTP requests. Avoid `:httpoison`, `:tesla`, and `:httpc`.

```elixir
# Preferred
{:ok, response} = Req.get(url)

# For streaming downloads
Req.get(url, into: File.stream!(path))
```

### Elixir Patterns

**List access** - Never use index syntax on lists:

```elixir
# WRONG
mylist[0]

# CORRECT
Enum.at(mylist, 0)
```

**Immutability** - Rebind block expression results:

```elixir
# WRONG
if connected?(socket) do
  socket = assign(socket, :val, val)
end

# CORRECT
socket =
  if connected?(socket) do
    assign(socket, :val, val)
  else
    socket
  end
```

**Changeset access** - Use `get_field/2`:

```elixir
# WRONG
changeset[:field]

# CORRECT
Ecto.Changeset.get_field(changeset, :field)
```


### Ecto Guidelines

- Preload associations when accessed in templates
- Use `:string` type for text fields
- Don't include programmatic fields (like `user_id`) in `cast` calls

## Testing

```bash
# Run all tests
mix test

# Run specific test file
mix test test/path/to/test.exs

# Run failed tests only
mix test --failed
```

Test assertions for API responses:

```elixir
# show/create/update - direct access
response = json_response(conn, 200)
assert response["id"] == character.id

# index - use plural key
response = json_response(conn, 200)
assert length(response["characters"]) == 2
```

## Database

- Uses PostgreSQL with UUID primary keys
- Test database: `shot_server_test`
- Development database: `shot_counter_local`

## Common Pitfalls

1. Don't use `String.to_atom/1` on user input (memory leak)
2. Don't nest multiple modules in the same file
3. Don't use map access syntax on structs
4. Phoenix router `scope` blocks include an optional alias prefix
5. `Phoenix.View` is not included by default in Phoenix 1.7+ projects, but may still be used where needed (e.g., for email templates). It is actively used in this codebase.
