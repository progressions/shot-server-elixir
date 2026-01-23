defmodule ShotElixir.Services.Notion.FromNotion do
  @moduledoc """
  Generic logic for updating local entities from Notion pages.

  Handles the common pattern shared by update_*_from_notion functions:
  - Token retrieval and validation
  - Notion API calls with error handling
  - Bot update detection (skip_bot_update?)
  - Attribute extraction via callbacks
  - Rich description fetching
  - Entity update with skip_notion_sync
  - Success/error logging
  - Exception handling

  Entity-specific logic is provided via callbacks in the config map.
  """

  require Logger

  alias ShotElixir.Notion
  alias ShotElixir.Repo
  alias ShotElixir.Services.Notion.{Config, Mappers}

  @doc """
  Update a local entity from its linked Notion page.

  ## Config Options

  Required:
  - `:entity_type` - String for logging (e.g., "site", "party")
  - `:update_fn` - Function to update the entity, arity 3: (entity, attrs, opts)

  Optional:
  - `:extract_attributes_fn` - Function to extract attributes from page, arity 2: (page, entity)
    Defaults to `entity_attributes_from_notion(page, entity.campaign_id)`
  - `:post_update_fn` - Function called after successful update, arity 2: (updated_entity, page)
  - `:add_image` - Boolean, whether to call add_image(page, entity) after update

  ## Examples

      update_from_notion(site, %{
        entity_type: "site",
        update_fn: &Sites.update_site/3,
        post_update_fn: &sync_site_attunements_from_notion/2
      })

  """
  def update_from_notion(entity, config, opts \\ [])

  def update_from_notion(%{notion_page_id: nil}, _config, _opts) do
    {:error, :no_page_id}
  end

  def update_from_notion(entity, config, opts) do
    entity = Repo.preload(entity, :campaign)
    token = Config.get_token(entity.campaign)
    entity_type = Map.fetch!(config, :entity_type)

    unless token do
      {:error, :no_notion_oauth_token}
    else
      opts = Keyword.put_new(opts, :token, token)
      payload = %{"page_id" => entity.notion_page_id}
      client = Config.client(opts)

      case client.get_page(entity.notion_page_id, token: token) do
        nil ->
          Logger.error("Failed to fetch Notion page: #{entity.notion_page_id}")
          log_sync_error(entity_type, entity.id, payload, %{}, "Notion page not found")
          {:error, :notion_page_not_found}

        %{"code" => error_code, "message" => message} = response ->
          Logger.error("Notion API error: #{error_code} - #{message}")
          log_sync_error(entity_type, entity.id, payload, response, "Notion API error: #{error_code} - #{message}")
          {:error, {:notion_api_error, error_code, message}}

        page when is_map(page) ->
          process_page(entity, page, config, opts, payload)
      end
    end
  rescue
    error ->
      entity_type = Map.get(config, :entity_type, "unknown")
      Logger.error("Failed to update #{entity_type} from Notion: #{Exception.message(error)}")
      log_sync_error(entity_type, entity.id, %{"page_id" => entity.notion_page_id}, %{}, "Exception: #{Exception.message(error)}")
      {:error, error}
  end

  defp process_page(entity, page, config, opts, payload) do
    entity_type = Map.fetch!(config, :entity_type)
    force = Keyword.get(opts, :force, false)

    if Config.skip_bot_update?(page, opts) and not force do
      Logger.info("Skipping update for #{entity_type} #{entity.id} as it was last edited by the bot")
      {:ok, entity}
    else
      token = Keyword.fetch!(opts, :token)
      attributes = extract_attributes(entity, page, config, token)

      update_fn = Map.fetch!(config, :update_fn)
      skip_notion_sync = Map.get(config, :skip_notion_sync, true)

      result =
        if skip_notion_sync do
          update_fn.(entity, attributes, skip_notion_sync: true)
        else
          update_fn.(entity, attributes)
        end

      case result do
        {:ok, updated_entity} ->
          run_post_update(updated_entity, page, config)
          Notion.log_success(entity_type, updated_entity.id, payload, page)
          {:ok, updated_entity}

        {:error, changeset} = error ->
          log_sync_error(entity_type, entity.id, payload, page, "Failed to update #{entity_type} from Notion: #{inspect(changeset)}")
          error
      end
    end
  end

  defp extract_attributes(entity, page, config, token) do
    extract_fn = Map.get(config, :extract_attributes_fn)

    attributes =
      if extract_fn do
        extract_fn.(page, entity)
      else
        Mappers.entity_attributes_from_notion(page, entity.campaign_id)
      end

    Mappers.add_rich_description(attributes, entity.notion_page_id, entity.campaign_id, token)
  end

  defp run_post_update(entity, page, config) do
    if post_fn = Map.get(config, :post_update_fn) do
      post_fn.(entity, page)
    end

    if Map.get(config, :add_image, false) do
      ShotElixir.Services.Notion.Images.add_image(page, entity)
    end

    :ok
  end

  defp log_sync_error(entity_type, entity_id, payload, response, message) do
    Notion.log_error(entity_type, entity_id, payload, response, message)
  end
end
