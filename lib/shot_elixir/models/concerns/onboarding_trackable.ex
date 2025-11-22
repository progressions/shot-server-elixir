defmodule ShotElixir.Models.Concerns.OnboardingTrackable do
  @moduledoc """
  Tracks onboarding milestones when entities are created.

  Include this in schemas that should trigger onboarding progress updates:
  - Campaign
  - Character
  - Fight
  - Site
  - Party
  - Faction
  """

  alias ShotElixir.Onboarding
  alias ShotElixir.Repo
  require Logger

  @doc """
  Call this after inserting a record to track the onboarding milestone.
  """
  def track_milestone(record) do
    Logger.info(
      "🎯 OnboardingTrackable: Tracking milestone for #{record.__struct__} (ID: #{record.id})"
    )

    # Skip tracking for template characters
    if skip_tracking?(record) do
      Logger.info(
        "⏭️ Skipping milestone tracking for template: #{Map.get(record, :name, "unnamed")}"
      )

      :ok
    else
      # Get the user - either directly or through campaign
      target_user = get_target_user(record)

      unless target_user do
        Logger.warning("❌ No user found for #{record.__struct__} (ID: #{record.id})")
        :ok
      else
        do_track_milestone(record, target_user)
      end
    end
  rescue
    e ->
      Logger.warning("❌ Failed to track onboarding milestone: #{inspect(e)}")
      Logger.warning("❌ #{Exception.format(:error, e, __STACKTRACE__)}")
  end

  defp do_track_milestone(record, target_user) do
    # Determine milestone type and field
    milestone_type = get_milestone_type(record)
    timestamp_field = String.to_atom("first_#{milestone_type}_created_at")

    Logger.info("🏆 Processing milestone: #{milestone_type} -> #{timestamp_field}")

    # Ensure user has onboarding progress record
    progress = Onboarding.ensure_onboarding_progress!(target_user)
    Logger.info("✅ Ensured onboarding progress record exists")

    # Only set if not already set (idempotent)
    current_value = Map.get(progress, timestamp_field)
    Logger.info("📊 Current #{timestamp_field}: #{inspect(current_value)}")

    if current_value == nil do
      case Onboarding.update_progress(progress, %{timestamp_field => DateTime.utc_now()}) do
        {:ok, _updated_progress} ->
          Logger.info("🎉 Set #{timestamp_field} for user #{target_user.email}")

        {:error, reason} ->
          Logger.warning("❌ Failed to update #{timestamp_field}: #{inspect(reason)}")
      end
    else
      Logger.info("⚠️ #{timestamp_field} already set, skipping")
    end
  end

  defp skip_tracking?(record) do
    # Skip template characters
    record.__struct__ == ShotElixir.Characters.Character &&
      Map.get(record, :is_template, false) == true
  end

  defp get_target_user(record) do
    cond do
      # Record has direct user association
      Map.has_key?(record, :user_id) && record.user_id != nil ->
        record = Repo.preload(record, :user, force: true)
        user = record.user

        if user do
          Logger.info("📍 Found user directly: #{user.email}")
          user
        end

      # Record has campaign with user
      Map.has_key?(record, :campaign_id) && record.campaign_id != nil ->
        record = Repo.preload(record, [campaign: :user], force: true)

        if record.campaign && record.campaign.user do
          Logger.info("📍 Found user through campaign: #{record.campaign.user.email}")
          record.campaign.user
        end

      true ->
        nil
    end
  end

  defp get_milestone_type(record) do
    # Extract module name (e.g., ShotElixir.Campaigns.Campaign -> "campaign")
    record.__struct__
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end
end
