defmodule ShotElixir.Workers.EmailWorker do
  @moduledoc """
  Background worker for sending emails via Oban.

  Handles all email delivery with retry logic and error handling.
  Supports multiple email types dispatched based on job args.
  """

  use Oban.Worker, queue: :emails, max_attempts: 3

  alias ShotElixir.Mailer
  alias ShotElixir.Emails.{UserEmail, AdminEmail}
  alias ShotElixir.Repo
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type} = args}) do
    Logger.info("Processing #{type} email job")

    args
    |> build_email()
    |> Mailer.deliver()
    |> case do
      {:ok, _metadata} ->
        Logger.info("Email sent successfully: #{type}")
        :ok

      {:error, reason} ->
        Logger.error("Email delivery failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Build invitation email
  defp build_email(%{"type" => "invitation", "invitation_id" => invitation_id}) do
    invitation =
      Repo.get!(ShotElixir.Invitations.Invitation, invitation_id)
      |> Repo.preload([:campaign, campaign: :user])

    UserEmail.invitation(invitation)
  end

  # Build welcome email
  defp build_email(%{"type" => "welcome", "user_id" => user_id}) do
    user = Repo.get!(ShotElixir.Accounts.User, user_id)
    UserEmail.welcome(user)
  end

  # Build confirmation instructions email
  defp build_email(%{
         "type" => "confirmation_instructions",
         "user_id" => user_id,
         "token" => token
       }) do
    user = Repo.get!(ShotElixir.Accounts.User, user_id)
    UserEmail.confirmation_instructions(user, token)
  end

  # Build password reset email
  defp build_email(%{
         "type" => "reset_password_instructions",
         "user_id" => user_id,
         "token" => token
       }) do
    user = Repo.get!(ShotElixir.Accounts.User, user_id)
    UserEmail.reset_password_instructions(user, token)
  end

  # Build joined campaign email
  defp build_email(%{
         "type" => "joined_campaign",
         "user_id" => user_id,
         "campaign_id" => campaign_id
       }) do
    user = Repo.get!(ShotElixir.Accounts.User, user_id)
    campaign = Repo.get!(ShotElixir.Campaigns.Campaign, campaign_id)
    UserEmail.joined_campaign(user, campaign)
  end

  # Build removed from campaign email
  defp build_email(%{
         "type" => "removed_from_campaign",
         "user_id" => user_id,
         "campaign_id" => campaign_id
       }) do
    user = Repo.get!(ShotElixir.Accounts.User, user_id)
    campaign = Repo.get!(ShotElixir.Campaigns.Campaign, campaign_id)
    UserEmail.removed_from_campaign(user, campaign)
  end

  # Build admin error notification email
  defp build_email(%{
         "type" => "admin_error",
         "campaign_id" => campaign_id,
         "error_message" => error_message
       }) do
    campaign = Repo.get!(ShotElixir.Campaigns.Campaign, campaign_id) |> Repo.preload(:user)
    AdminEmail.blob_sequence_error(campaign, error_message)
  end

  # Fallback for unknown email types
  defp build_email(%{"type" => type}) do
    Logger.error("Unknown email type: #{type}")
    raise "Unknown email type: #{type}"
  end
end
