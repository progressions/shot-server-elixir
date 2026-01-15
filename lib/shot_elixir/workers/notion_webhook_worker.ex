defmodule ShotElixir.Workers.NotionWebhookWorker do
  @moduledoc """
  Processes incoming Notion webhook events.

  This worker handles real-time updates from Notion by:
  1. Looking up the Chi War entity by Notion page ID
  2. Fetching the latest data from Notion
  3. Updating the local entity (with skip_notion_sync to prevent ping-pong)
  4. Broadcasting the change via Phoenix Channels

  ## Idempotency

  Uses Oban's `unique` feature keyed by `event_id` to prevent duplicate processing.
  Notion may send the same event multiple times (retries on non-2xx responses).

  ## Supported Event Types

  - `page.properties_updated` - Page properties changed (name, attributes)
  - `page.content_updated` - Page body content changed (description, notes)
  - `page.deleted` / `page.restored` - Soft delete handling
  """

  use Oban.Worker,
    queue: :webhooks,
    max_attempts: 3,
    unique: [
      period: 3600,
      fields: [:args],
      keys: [:event_id]
    ]

  require Logger

  alias ShotElixir.Repo
  alias ShotElixir.Characters.Character
  alias ShotElixir.Sites.Site
  alias ShotElixir.Parties.Party
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Adventures.Adventure
  alias ShotElixir.Services.NotionService
  alias ShotElixirWeb.CampaignChannel

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    event_id = args["event_id"]
    event_type = args["event_type"]
    entity_id = args["entity_id"]

    Logger.info("Processing Notion webhook: event_id=#{event_id} type=#{event_type}")

    case find_entity_by_notion_page_id(entity_id) do
      {:ok, entity_type, entity} ->
        process_event(event_type, entity_type, entity)

      {:error, :not_found} ->
        # Page not linked to any Chi War entity - this is normal for pages
        # in Notion that aren't synced with Chi War
        Logger.debug("Notion page #{entity_id} not linked to any Chi War entity")
        :ok
    end
  end

  @doc """
  Finds a Chi War entity by its Notion page ID.

  Searches across all entity types that support Notion sync:
  - Characters
  - Sites
  - Parties
  - Factions
  - Junctures
  - Adventures

  Returns `{:ok, entity_type, entity}` or `{:error, :not_found}`.
  """
  def find_entity_by_notion_page_id(nil), do: {:error, :not_found}

  def find_entity_by_notion_page_id(page_id) do
    # Normalize page_id (Notion sometimes sends with/without dashes)
    normalized_page_id = normalize_uuid(page_id)

    cond do
      character = Repo.get_by(Character, notion_page_id: normalized_page_id) ->
        {:ok, :character, Repo.preload(character, :campaign)}

      site = Repo.get_by(Site, notion_page_id: normalized_page_id) ->
        {:ok, :site, Repo.preload(site, :campaign)}

      party = Repo.get_by(Party, notion_page_id: normalized_page_id) ->
        {:ok, :party, Repo.preload(party, :campaign)}

      faction = Repo.get_by(Faction, notion_page_id: normalized_page_id) ->
        {:ok, :faction, Repo.preload(faction, :campaign)}

      juncture = Repo.get_by(Juncture, notion_page_id: normalized_page_id) ->
        {:ok, :juncture, Repo.preload(juncture, :campaign)}

      adventure = Repo.get_by(Adventure, notion_page_id: normalized_page_id) ->
        {:ok, :adventure, Repo.preload(adventure, :campaign)}

      true ->
        {:error, :not_found}
    end
  end

  # Process different event types
  defp process_event(event_type, entity_type, entity)
       when event_type in ["page.properties_updated", "page.content_updated"] do
    Logger.info("Syncing #{entity_type} #{entity.id} from Notion (#{event_type})")

    result = sync_entity_from_notion(entity_type, entity)

    case result do
      {:ok, updated_entity} ->
        # Broadcast update via Phoenix Channel
        broadcast_entity_update(entity_type, updated_entity)
        :ok

      {:error, reason} ->
        Logger.error("Failed to sync #{entity_type} from Notion: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_event("page.deleted", entity_type, entity) do
    Logger.info("Notion page deleted for #{entity_type} #{entity.id}")
    # For now, just log - could implement soft delete logic here
    :ok
  end

  defp process_event("page.restored", entity_type, entity) do
    Logger.info("Notion page restored for #{entity_type} #{entity.id}")
    # Sync the restored content
    sync_entity_from_notion(entity_type, entity)
    :ok
  end

  defp process_event(event_type, entity_type, entity) do
    Logger.debug("Ignoring #{event_type} event for #{entity_type} #{entity.id}")
    :ok
  end

  # Sync entity from Notion using existing NotionService functions
  defp sync_entity_from_notion(:character, character) do
    NotionService.update_character_from_notion(character)
  end

  defp sync_entity_from_notion(:site, site) do
    NotionService.update_site_from_notion(site)
  end

  defp sync_entity_from_notion(:party, party) do
    NotionService.update_party_from_notion(party)
  end

  defp sync_entity_from_notion(:faction, faction) do
    NotionService.update_faction_from_notion(faction)
  end

  defp sync_entity_from_notion(:juncture, juncture) do
    NotionService.update_juncture_from_notion(juncture)
  end

  defp sync_entity_from_notion(:adventure, adventure) do
    NotionService.update_adventure_from_notion(adventure)
  end

  # Broadcast entity update via CampaignChannel
  defp broadcast_entity_update(entity_type, entity) do
    campaign_id = entity.campaign_id

    if campaign_id do
      entity_class = entity_type_to_class(entity_type)
      CampaignChannel.broadcast_entity_reload(campaign_id, entity_class)

      Logger.debug("Broadcast #{entity_class} reload to campaign #{campaign_id}")
    end
  end

  defp entity_type_to_class(:character), do: "Character"
  defp entity_type_to_class(:site), do: "Site"
  defp entity_type_to_class(:party), do: "Party"
  defp entity_type_to_class(:faction), do: "Faction"
  defp entity_type_to_class(:juncture), do: "Juncture"
  defp entity_type_to_class(:adventure), do: "Adventure"

  # Normalize UUID format (Notion sometimes sends without dashes)
  defp normalize_uuid(uuid) when is_binary(uuid) do
    # If already has dashes, return as-is
    if String.contains?(uuid, "-") do
      uuid
    else
      # Insert dashes: 8-4-4-4-12
      <<a::binary-size(8), b::binary-size(4), c::binary-size(4), d::binary-size(4),
        e::binary-size(12)>> = uuid

      "#{a}-#{b}-#{c}-#{d}-#{e}"
    end
  rescue
    _ -> uuid
  end
end
