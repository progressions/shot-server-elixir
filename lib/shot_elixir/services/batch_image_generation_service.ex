defmodule ShotElixir.Services.BatchImageGenerationService do
  @moduledoc """
  Service for batch AI image generation for entities without images.

  Allows gamemasters to generate images for all entities (Characters, Sites,
  Factions, Parties, Vehicles) in a campaign that don't currently have images.
  """

  import Ecto.Query
  alias ShotElixir.Repo
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Characters.Character
  alias ShotElixir.Sites.Site
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Parties.Party
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.ActiveStorage.Attachment
  alias ShotElixir.Workers.BatchImageGenerationWorker
  require Logger

  @entity_types [
    {Character, "Character"},
    {Site, "Site"},
    {Faction, "Faction"},
    {Party, "Party"},
    {Vehicle, "Vehicle"}
  ]

  @doc """
  Finds all entities in a campaign that don't have images.
  Returns a list of {entity_id, entity_type} tuples.

  ## Examples

      iex> find_entities_without_images(campaign_id)
      [{character_id, "Character"}, {site_id, "Site"}, ...]
  """
  def find_entities_without_images(campaign_id) do
    @entity_types
    |> Enum.flat_map(fn {module, type_name} ->
      find_entities_without_images_for_type(campaign_id, module, type_name)
    end)
  end

  defp find_entities_without_images_for_type(campaign_id, module, type_name) do
    # Use a subquery approach to avoid binding issues
    base_query =
      from(e in module,
        left_join: a in Attachment,
        on: a.record_type == ^type_name and a.record_id == e.id and a.name == "image",
        where: e.campaign_id == ^campaign_id and e.active == true,
        where: is_nil(a.id),
        select: {e.id, ^type_name}
      )

    Repo.all(base_query)
  end

  @doc """
  Starts batch image generation for a campaign.
  Sets batch_image_status to "generating" and enqueues jobs for each entity.

  Returns {:ok, total_count} or {:error, reason}.

  ## Examples

      iex> start_batch_generation(campaign_id)
      {:ok, 45}
  """
  def start_batch_generation(campaign_id) do
    with {:ok, campaign} <- get_campaign(campaign_id),
         :ok <- validate_not_in_progress(campaign),
         entities <- find_entities_without_images(campaign_id),
         :ok <- validate_entities_exist(entities) do
      total = length(entities)

      # Update campaign status
      campaign
      |> Ecto.Changeset.change(%{
        batch_image_status: "generating",
        batch_images_total: total,
        batch_images_completed: 0
      })
      |> Repo.update!()

      # Broadcast initial status
      broadcast_batch_status(campaign_id, campaign.user_id, "generating", 0, total)

      # Enqueue jobs for each entity
      Enum.each(entities, fn {entity_id, entity_type} ->
        %{
          "entity_type" => entity_type,
          "entity_id" => entity_id,
          "campaign_id" => campaign_id
        }
        |> BatchImageGenerationWorker.new()
        |> Oban.insert()
      end)

      Logger.info(
        "[BatchImageGenerationService] Started batch generation for campaign #{campaign_id}: #{total} entities"
      )

      {:ok, total}
    end
  end

  @doc """
  Increments the batch image completion counter for a campaign.
  Uses atomic SQL UPDATE to prevent race conditions with parallel workers.
  """
  def increment_completion(campaign_id) do
    query =
      from(c in Campaign,
        where: c.id == ^campaign_id,
        update: [set: [batch_images_completed: coalesce(c.batch_images_completed, 0) + 1]],
        select: %{
          batch_images_completed: c.batch_images_completed,
          batch_images_total: c.batch_images_total,
          user_id: c.user_id
        }
      )

    case Repo.update_all(query, []) do
      {1, [result]} ->
        new_completed = result.batch_images_completed || 0
        images_total = result.batch_images_total
        user_id = result.user_id

        # Broadcast progress
        broadcast_batch_status(campaign_id, user_id, "generating", new_completed, images_total)

        Logger.debug(
          "[BatchImageGenerationService] Batch image progress: #{new_completed}/#{images_total}"
        )

        # Check if all images are done
        if new_completed >= (images_total || 0) do
          campaign = Repo.get(Campaign, campaign_id)
          if campaign, do: finalize_batch_generation(campaign)
        end

        {:ok, new_completed}

      {0, _} ->
        Logger.warning(
          "[BatchImageGenerationService] Campaign #{campaign_id} not found for increment"
        )

        {:error, :not_found}

      other ->
        Logger.error(
          "[BatchImageGenerationService] Unexpected result from increment: #{inspect(other)}"
        )

        {:error, :unexpected_result}
    end
  end

  @doc """
  Marks batch image generation as complete.
  Uses conditional update to prevent race conditions.
  """
  def finalize_batch_generation(%Campaign{} = campaign) do
    Logger.info(
      "[BatchImageGenerationService] Finalizing batch generation for campaign #{campaign.id}"
    )

    # Only update if status is still "generating"
    query =
      from(c in Campaign,
        where: c.id == ^campaign.id and c.batch_image_status == "generating",
        update: [
          set: [
            batch_image_status: "complete"
          ]
        ]
      )

    case Repo.update_all(query, []) do
      {1, _} ->
        # Successfully updated - broadcast completion
        broadcast_batch_status(campaign.id, campaign.user_id, "complete", nil, nil)

        Logger.info(
          "[BatchImageGenerationService] Campaign #{campaign.id} batch image generation complete!"
        )

        :ok

      {0, _} ->
        # Already finalized by another worker
        Logger.debug(
          "[BatchImageGenerationService] Campaign #{campaign.id} already finalized by another worker"
        )

        :already_complete
    end
  end

  # Private helpers

  defp get_campaign(campaign_id) do
    case Repo.get(Campaign, campaign_id) do
      nil -> {:error, :campaign_not_found}
      campaign -> {:ok, campaign}
    end
  end

  defp validate_not_in_progress(%Campaign{batch_image_status: status})
       when status in [nil, "complete"] do
    :ok
  end

  defp validate_not_in_progress(%Campaign{batch_image_status: status}) do
    {:error, {:already_in_progress, status}}
  end

  defp validate_entities_exist([]) do
    {:error, :no_entities_without_images}
  end

  defp validate_entities_exist(_entities) do
    :ok
  end

  defp broadcast_batch_status(campaign_id, user_id, status, completed, total) do
    campaign_data = %{
      id: campaign_id,
      batch_image_status: status,
      batch_images_total: total,
      batch_images_completed: completed
    }

    # Wrap in "campaign" key so frontend subscribeToEntity("campaign", ...) receives it
    payload = %{campaign: campaign_data}

    # Broadcast to campaign channel
    Phoenix.PubSub.broadcast!(
      ShotElixir.PubSub,
      "campaign:#{campaign_id}",
      {:campaign_broadcast, payload}
    )

    # Also broadcast to user channel
    if user_id do
      Phoenix.PubSub.broadcast!(
        ShotElixir.PubSub,
        "user:#{user_id}",
        {:user_broadcast, payload}
      )
    end
  end
end
