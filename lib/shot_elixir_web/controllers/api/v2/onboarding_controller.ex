defmodule ShotElixirWeb.Api.V2.OnboardingController do
  use ShotElixirWeb, :controller

  require Logger
  alias ShotElixir.Onboarding
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # POST /api/v2/onboarding/dismiss_congratulations
  # Marks when a user dismisses congratulations message
  def dismiss_congratulations(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    try do
      progress = Onboarding.ensure_onboarding_progress!(current_user)

      {:ok, updated_progress} = Onboarding.dismiss_congratulations(progress)
      render(conn, "success.json", onboarding_progress: updated_progress)
    rescue
      error ->
        Logger.error("Failed to dismiss congratulations for user #{current_user.id}: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> render("error.json", error: "Failed to dismiss congratulations. Please try again.")
    end
  end

  # PATCH/PUT /api/v2/onboarding
  # Updates onboarding progress milestones
  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    try do
      progress = Onboarding.ensure_onboarding_progress!(current_user)
      onboarding_params = extract_onboarding_params(params)

      {:ok, updated_progress} = Onboarding.update_progress(progress, onboarding_params)
      render(conn, "success.json", onboarding_progress: updated_progress)
    rescue
      error ->
        Logger.error("Failed to update onboarding progress for user #{current_user.id}: #{inspect(error)}")

        conn
        |> put_status(:internal_server_error)
        |> render("error.json", error: "Failed to update onboarding progress. Please try again.")
    end
  end

  # Private helper functions
  defp extract_onboarding_params(params) do
    onboarding_progress_params = params["onboarding_progress"] || %{}

    # Convert datetime strings to DateTime structs if needed
    Enum.reduce(onboarding_progress_params, %{}, fn {key, value}, acc ->
      case key do
        key when key in [
          "first_campaign_created_at",
          "first_campaign_activated_at",
          "first_character_created_at",
          "first_fight_created_at",
          "first_faction_created_at",
          "first_party_created_at",
          "first_site_created_at",
          "congratulations_dismissed_at"
        ] ->
          parsed_value = parse_datetime(value)
          Map.put(acc, key, parsed_value)

        _ ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} -> datetime
      {:error, _} ->
        # Try parsing without timezone
        case NaiveDateTime.from_iso8601(value) do
          {:ok, naive_datetime} -> DateTime.from_naive!(naive_datetime, "Etc/UTC")
          {:error, _} -> value
        end
    end
  end
  defp parse_datetime(value), do: value
end
