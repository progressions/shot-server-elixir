defmodule ShotElixirWeb.Api.V2.MediaLibraryController do
  @moduledoc """
  Controller for the Media Library feature.
  Provides endpoints for listing, viewing, deleting, duplicating, and attaching images.
  """

  use ShotElixirWeb, :controller

  alias ShotElixir.Media
  alias ShotElixir.Media.MediaImage
  alias ShotElixir.Guardian
  alias ShotElixir.Campaigns
  alias ShotElixirWeb.CampaignChannel

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  Lists all images for the current campaign with optional filtering and sorting.

  ## Query Parameters
    - status: "orphan", "attached", or "all" (default: "all")
    - source: "upload", "ai_generated", or "all" (default: "all")
    - entity_type: Filter by entity type (e.g., "Character")
    - sort: Sort field - "inserted_at", "updated_at", "filename", "byte_size", "entity_type" (default: "inserted_at")
    - order: Sort direction - "asc" or "desc" (default: "desc")
    - page: Page number (default: 1)
    - per_page: Items per page (default: 50)
  """
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with campaign_id when not is_nil(campaign_id) <- current_user.current_campaign_id,
         result <- Media.list_campaign_images(campaign_id, params) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.MediaLibraryView)
      |> render("index.json", result)
    else
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No current campaign set"})
    end
  end

  @doc """
  Shows a single image with full details.
  """
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %MediaImage{} = image <- Media.get_image(id),
         :ok <- authorize_image_access(image, current_user) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.MediaLibraryView)
      |> render("show.json", image: image)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Deletes a single image.
  Removes from database, ImageKit, and un-associates from entity if attached.
  """
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %MediaImage{} = image <- Media.get_image(id),
         :ok <- authorize_image_access(image, current_user),
         :ok <- require_gamemaster(current_user, image.campaign_id),
         {:ok, _deleted} <- Media.delete_image(image) do
      CampaignChannel.broadcast_entity_reload(image.campaign_id, "Image")
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, :unauthorized} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Bulk deletes multiple images.

  ## Body Parameters
    - ids: List of image IDs to delete
  """
  def bulk_delete(conn, %{"ids" => ids}) when is_list(ids) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id

    # Verify all images belong to the current campaign and user is gamemaster
    with :ok <- require_gamemaster(current_user, campaign_id),
         :ok <- verify_images_in_campaign(ids, campaign_id),
         {:ok, result} <- Media.bulk_delete_images(ids) do
      CampaignChannel.broadcast_entity_reload(campaign_id, "Image")

      conn
      |> put_status(:ok)
      |> json(%{
        deleted: result.deleted,
        failed: result.failed
      })
    else
      {:error, :unauthorized} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  def bulk_delete(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required 'ids' parameter"})
  end

  @doc """
  Duplicates an image within ImageKit and creates a new database record.
  The copy is always created as an orphan.
  """
  def duplicate(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %MediaImage{} = image <- Media.get_image(id),
         :ok <- authorize_image_access(image, current_user),
         :ok <- require_gamemaster(current_user, image.campaign_id),
         {:ok, new_image} <- Media.duplicate_image(image) do
      CampaignChannel.broadcast_entity_reload(image.campaign_id, "Image")

      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.MediaLibraryView)
      |> render("show.json", image: new_image)
    else
      nil -> {:error, :not_found}
      {:error, :unauthorized} -> {:error, :unauthorized}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Attaches an orphan image to an entity.

  ## Body Parameters
    - entity_type: "Character", "Vehicle", etc.
    - entity_id: UUID of the entity
  """
  def attach(conn, %{"id" => id, "entity_type" => entity_type, "entity_id" => entity_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %MediaImage{} = image <- Media.get_image(id),
         :ok <- authorize_image_access(image, current_user),
         :ok <- require_gamemaster(current_user, image.campaign_id),
         :ok <- validate_entity_type(entity_type),
         {:ok, updated_image} <- Media.attach_to_entity(image, entity_type, entity_id) do
      CampaignChannel.broadcast_entity_reload(image.campaign_id, "Image")

      conn
      |> put_status(:ok)
      |> put_view(ShotElixirWeb.Api.V2.MediaLibraryView)
      |> render("show.json", image: updated_image)
    else
      nil ->
        {:error, :not_found}

      {:error, :invalid_entity_type} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Invalid entity type"})

      {:error, :unauthorized} ->
        {:error, :unauthorized}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def attach(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: entity_type, entity_id"})
  end

  @doc """
  Returns a download URL for the image.
  This just returns the ImageKit URL which can be downloaded directly.
  """
  def download(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %MediaImage{} = image <- Media.get_image(id),
         :ok <- authorize_image_access(image, current_user) do
      conn
      |> put_status(:ok)
      |> json(%{
        download_url: image.imagekit_url,
        filename: image.filename || "image.jpg"
      })
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Searches images by AI-generated tags.

  ## Query Parameters
    - q: Search query (comma-separated terms)
    - page: Page number (default: 1)
    - per_page: Items per page (default: 50)

  ## Example
    GET /api/v2/media_library/search?q=warrior,cartoon
  """
  def search(conn, %{"q" => query} = params) when is_binary(query) and query != "" do
    current_user = Guardian.Plug.current_resource(conn)

    with campaign_id when not is_nil(campaign_id) <- current_user.current_campaign_id do
      # Parse search terms (comma or space separated)
      search_terms =
        query
        |> String.split(~r/[,\s]+/)
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&(&1 != ""))

      result = Media.search_by_ai_tags(campaign_id, search_terms, params)

      conn
      |> put_view(ShotElixirWeb.Api.V2.MediaLibraryView)
      |> render("search.json", result)
    else
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No current campaign set"})
    end
  end

  def search(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required 'q' parameter"})
  end

  @doc """
  Returns all unique AI tag names for the current campaign.
  Useful for autocomplete or tag clouds.
  """
  def ai_tags(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    with campaign_id when not is_nil(campaign_id) <- current_user.current_campaign_id do
      tags = Media.list_ai_tags(campaign_id)

      conn
      |> put_status(:ok)
      |> json(%{tags: tags})
    else
      nil ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "No current campaign set"})
    end
  end

  # Authorization helpers

  defp authorize_image_access(%MediaImage{campaign_id: campaign_id}, current_user) do
    user_campaigns = Campaigns.get_user_campaigns(current_user.id)

    if Enum.any?(user_campaigns, fn c -> c.id == campaign_id end) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp require_gamemaster(current_user, campaign_id) do
    user_campaigns = Campaigns.get_user_campaigns(current_user.id)
    is_member = Enum.any?(user_campaigns, fn c -> c.id == campaign_id end)

    cond do
      current_user.admin -> :ok
      current_user.gamemaster && is_member -> :ok
      true -> {:error, :unauthorized}
    end
  end

  defp verify_images_in_campaign(ids, campaign_id) do
    # Check that all image IDs belong to the campaign with a single query
    import Ecto.Query

    matching_count =
      from(i in MediaImage,
        where: i.id in ^ids and i.campaign_id == ^campaign_id,
        select: count(i.id)
      )
      |> ShotElixir.Repo.one()

    if matching_count == length(ids) do
      :ok
    else
      {:error, :unauthorized}
    end
  end

  defp validate_entity_type(entity_type) do
    if entity_type in MediaImage.valid_entity_types() do
      :ok
    else
      {:error, :invalid_entity_type}
    end
  end
end
