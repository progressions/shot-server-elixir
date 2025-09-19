defmodule ShotElixirWeb.Api.V2.OnboardingView do
  def render("success.json", %{onboarding_progress: progress}) do
    %{
      success: true,
      onboarding_progress: render_onboarding_progress(progress)
    }
  end

  def render("error.json", %{errors: errors}) do
    %{
      success: false,
      errors: translate_errors(errors)
    }
  end

  def render("error.json", %{error: error}) do
    %{
      success: false,
      errors: %{base: [error]}
    }
  end

  defp render_onboarding_progress(progress) do
    %{
      id: progress.id,
      user_id: progress.user_id,
      first_campaign_created_at: progress.first_campaign_created_at,
      first_campaign_activated_at: progress.first_campaign_activated_at,
      first_character_created_at: progress.first_character_created_at,
      first_fight_created_at: progress.first_fight_created_at,
      first_faction_created_at: progress.first_faction_created_at,
      first_party_created_at: progress.first_party_created_at,
      first_site_created_at: progress.first_site_created_at,
      congratulations_dismissed_at: progress.congratulations_dismissed_at,
      created_at: progress.created_at,
      updated_at: progress.updated_at
    }
  end

  defp translate_errors(changeset) when is_map(changeset) do
    if Map.has_key?(changeset, :errors) do
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    else
      changeset
    end
  end

  defp translate_errors(errors), do: errors
end
