# ImageKit Implementation Plan for Shot-Elixir

## Overview

Since there's no official ImageKit SDK for Elixir, we'll create a custom integration that:
1. Uses Arc for file upload handling
2. Uploads directly to ImageKit via their REST API
3. Generates ImageKit CDN URLs for stored files
4. Maintains compatibility with the Rails implementation

## Architecture Design

### Option 1: Arc + ImageKit REST API (Recommended)

```elixir
# Flow:
1. Client uploads file → Phoenix controller
2. Arc handles file processing/validation
3. Custom ImageKit uploader sends to ImageKit API
4. Store ImageKit file ID in database
5. Generate CDN URLs on demand
```

### Option 2: Direct S3 + ImageKit URL Generation

```elixir
# Flow:
1. Upload to S3 via Arc
2. Configure ImageKit to use S3 as external storage
3. Generate ImageKit transformation URLs
```

## Implementation Steps

### Step 1: Add Dependencies

```elixir
# mix.exs
defp deps do
  [
    # File upload handling
    {:arc, "~> 0.11.0"},

    # HTTP client for ImageKit API
    {:req, "~> 0.4.0"},  # or {:httpoison, "~> 2.0"}

    # Image processing (optional)
    {:image, "~> 0.62.0"},

    # Caching
    {:cachex, "~> 3.6"}
  ]
end
```

### Step 2: Create ImageKit Service Module

```elixir
# lib/shot_elixir/services/imagekit_service.ex
defmodule ShotElixir.Services.ImagekitService do
  @base_url "https://api.imagekit.io/v1"
  @upload_url "https://upload.imagekit.io/api/v1/files/upload"

  def upload_file(file_path, options \\ %{}) do
    # Read file
    {:ok, file_content} = File.read(file_path)
    base64_file = Base.encode64(file_content)

    # Prepare upload data
    body = %{
      file: base64_file,
      fileName: options[:file_name] || Path.basename(file_path),
      folder: "/chi-war-#{env()}/#{options[:folder]}",
      tags: options[:tags] || [],
      useUniqueFileName: true
    }

    # Make API request
    headers = [
      {"Authorization", "Basic #{auth_token()}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(@upload_url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, parse_response(response)}
      {:error, reason} ->
        {:error, reason}
    end
  end

  def delete_file(file_id) do
    url = "#{@base_url}/files/#{file_id}"
    headers = [{"Authorization", "Basic #{auth_token()}"}]

    Req.delete(url, headers: headers)
  end

  def generate_url(file_id, transformations \\ []) do
    base = "https://ik.imagekit.io/#{imagekit_id()}/chi-war-#{env()}"
    transforms = build_transformation_string(transformations)

    if transforms == "" do
      "#{base}/#{file_id}"
    else
      "#{base}/#{transforms}/#{file_id}"
    end
  end

  defp auth_token do
    Base.encode64("#{private_key()}:")
  end

  defp private_key do
    Application.get_env(:shot_elixir, :imagekit)[:private_key]
  end

  defp public_key do
    Application.get_env(:shot_elixir, :imagekit)[:public_key]
  end

  defp imagekit_id do
    Application.get_env(:shot_elixir, :imagekit)[:id]
  end

  defp env do
    Application.get_env(:shot_elixir, :environment) || "development"
  end
end
```

### Step 3: Create Arc Uploader Module

```elixir
# lib/shot_elixir/uploaders/image_uploader.ex
defmodule ShotElixir.Uploaders.ImageUploader do
  use Arc.Definition

  @versions [:original, :thumb, :medium]
  @extension_whitelist ~w(.jpg .jpeg .gif .png .webp)

  # Validate file
  def validate({file, _}) do
    file_extension = file.file_name |> Path.extname() |> String.downcase()
    Enum.member?(@extension_whitelist, file_extension)
  end

  # Define transformations
  def transform(:thumb, _) do
    {:convert, "-strip -thumbnail 150x150^ -gravity center -extent 150x150"}
  end

  def transform(:medium, _) do
    {:convert, "-strip -thumbnail 500x500>"}
  end

  # Override storage to use ImageKit
  def store({file, scope}) do
    case ShotElixir.Services.ImagekitService.upload_file(
      file.path,
      %{
        file_name: file.file_name,
        folder: folder_for_scope(scope),
        tags: tags_for_scope(scope)
      }
    ) do
      {:ok, response} ->
        # Store ImageKit file_id in metadata
        {:ok, response.file_id}
      error ->
        error
    end
  end

  defp folder_for_scope(%{__struct__: module}) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp tags_for_scope(scope) do
    [scope.__struct__ |> to_string()]
  end
end
```

### Step 4: Create WithImagekit Concern (Elixir Version)

```elixir
# lib/shot_elixir/models/concerns/with_imagekit.ex
defmodule ShotElixir.Models.Concerns.WithImagekit do
  defmacro __using__(_opts) do
    quote do
      # Add image_data field to store ImageKit metadata
      field :image_data, :map, default: %{}
      field :image_url, :string, virtual: true

      # Callbacks
      after_load :load_image_url

      # Upload image
      def upload_image(%__MODULE__{} = record, %Plug.Upload{} = upload) do
        case ShotElixir.Uploaders.ImageUploader.store({upload, record}) do
          {:ok, file_id} ->
            changeset = Ecto.Changeset.change(record, %{
              image_data: %{
                "file_id" => file_id,
                "uploaded_at" => DateTime.utc_now()
              }
            })
            Repo.update(changeset)
          error ->
            error
        end
      end

      # Generate image URL with caching
      defp load_image_url(record) do
        if file_id = get_in(record.image_data, ["file_id"]) do
          cache_key = "image_url:#{record.__struct__}:#{record.id}:#{file_id}"

          url = Cachex.fetch!(
            :image_cache,
            cache_key,
            fn _key ->
              {:commit, ShotElixir.Services.ImagekitService.generate_url(file_id)}
            end
          )

          %{record | image_url: url}
        else
          record
        end
      end

      # Clear cache on update
      def clear_image_cache(%__MODULE__{} = record) do
        if file_id = get_in(record.image_data, ["file_id"]) do
          cache_key = "image_url:#{record.__struct__}:#{record.id}:#{file_id}"
          Cachex.del(:image_cache, cache_key)
        end
      end
    end
  end
end
```

### Step 5: Update Character Schema

```elixir
# lib/shot_elixir/characters/character.ex
defmodule ShotElixir.Characters.Character do
  use Ecto.Schema
  use ShotElixir.Models.Concerns.WithImagekit  # Add this

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "characters" do
    field :name, :string
    field :archetype, :string
    # ... other fields ...

    # Image fields handled by WithImagekit concern
    # field :image_data, :map (added by concern)
    # field :image_url, :string, virtual: true (added by concern)

    timestamps()
  end
end
```

### Step 6: Update Controller for Image Uploads

```elixir
# lib/shot_elixir_web/controllers/api/v2/character_controller.ex
defmodule ShotElixirWeb.Api.V2.CharacterController do
  # ... existing code ...

  def update(conn, %{"id" => id, "character" => character_params}) do
    character = Characters.get_character!(id)

    # Handle image upload if present
    character =
      case Map.get(character_params, "image") do
        %Plug.Upload{} = upload ->
          {:ok, updated} = character.upload_image(upload)
          updated
        _ ->
          character
      end

    # Continue with normal update
    case Characters.update_character(character, character_params) do
      {:ok, character} ->
        render(conn, "show.json", character: character)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", changeset: changeset)
    end
  end
end
```

### Step 7: Configuration

```elixir
# config/config.exs
config :shot_elixir, :imagekit,
  private_key: System.get_env("IMAGEKIT_PRIVATE_KEY"),
  public_key: System.get_env("IMAGEKIT_PUBLIC_KEY"),
  id: System.get_env("IMAGEKIT_ID") || "nvqgwnjgv"

# Configure Cachex for image URL caching
config :shot_elixir, :cachex,
  caches: [
    image_cache: [
      limit: 10_000,
      ttl: :timer.hours(1)
    ]
  ]
```

### Step 8: Add Cachex to Application Supervisor

```elixir
# lib/shot_elixir/application.ex
def start(_type, _args) do
  children = [
    # ... existing children ...
    {Cachex, name: :image_cache}
  ]

  opts = [strategy: :one_for_one, name: ShotElixir.Supervisor]
  Supervisor.start_link(children, opts)
end
```

## Testing Strategy

```elixir
# test/shot_elixir/services/imagekit_service_test.exs
defmodule ShotElixir.Services.ImagekitServiceTest do
  use ExUnit.Case
  import Mock

  test "uploads file successfully" do
    with_mock Req, [post: fn(_, _, _) ->
      {:ok, %{status: 200, body: %{"fileId" => "test123"}}}
    end] do
      assert {:ok, %{file_id: "test123"}} =
        ImagekitService.upload_file("test.jpg")
    end
  end

  test "generates correct CDN URL" do
    url = ImagekitService.generate_url("file123", [])
    assert url =~ "https://ik.imagekit.io/"
    assert url =~ "file123"
  end
end
```

## Migration from Rails

To ensure smooth migration:

1. **Database Compatibility**: Store ImageKit file IDs in a JSONB column matching Rails
2. **URL Format**: Generate URLs in the same format as Rails
3. **API Response**: Ensure JSON responses include `image_url` field
4. **Caching Strategy**: Match Rails cache TTL (1 hour)

## Environment Variables Required

```bash
# .env
IMAGEKIT_PRIVATE_KEY=your_private_key_here
IMAGEKIT_PUBLIC_KEY=your_public_key_here
IMAGEKIT_ID=nvqgwnjgv
```

## Deployment Considerations

1. **API Rate Limits**: ImageKit has rate limits, implement retry logic
2. **Error Handling**: Gracefully handle upload failures
3. **Monitoring**: Log all ImageKit API calls for debugging
4. **Fallbacks**: Consider fallback to S3 if ImageKit is down

## Timeline

- Day 1-2: Set up Arc and basic file handling
- Day 3-4: Implement ImageKit service module
- Day 5: Integrate with controllers and schemas
- Day 6: Testing and debugging
- Day 7: Documentation and deployment prep

This implementation will provide full ImageKit support for the Phoenix API, maintaining compatibility with the Rails implementation while using Elixir idioms and best practices.