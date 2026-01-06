defmodule ShotElixir.Emails.UserEmail do
  @moduledoc """
  User-facing email templates.

  Handles all transactional emails sent to users including invitations,
  confirmations, password resets, and campaign notifications.
  """

  import Swoosh.Email
  alias ShotElixirWeb.EmailView

  @from_email "admin@chiwar.net"
  @from_name "Chi War"

  @doc """
  Welcome email sent after user registration.
  """
  def welcome(user) do
    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Welcome to the Chi War!")
    |> html_body(render_template("welcome.html", %{user: user}))
  end

  @doc """
  Invitation email sent when gamemaster invites a new player.
  """
  def invitation(invitation) do
    campaign = invitation.campaign
    root_url = build_root_url()
    invitation_url = "#{root_url}/redeem/#{invitation.id}"

    new()
    |> to(invitation.email)
    |> from({@from_name, @from_email})
    |> subject("You have been invited to join #{campaign.name} in the Chi War!")
    |> html_body(
      render_template("invitation.html", %{
        invitation: invitation,
        campaign: campaign,
        invitation_url: invitation_url,
        root_url: root_url
      })
    )
  end

  @doc """
  Confirmation instructions email sent on user registration.
  Subject varies based on whether user has a pending invitation.
  """
  def confirmation_instructions(user, token) do
    {subject, template_assigns} =
      case user.pending_invitation_id do
        nil ->
          {"Confirm your account - Welcome to the Chi War!", %{invitation: nil, campaign: nil}}

        invitation_id ->
          invitation =
            ShotElixir.Repo.get(ShotElixir.Invitations.Invitation, invitation_id)
            |> ShotElixir.Repo.preload(:campaign)

          campaign = invitation && invitation.campaign

          subject =
            if campaign do
              "Confirm your account to join #{campaign.name} in the Chi War!"
            else
              "Confirm your account - Welcome to the Chi War!"
            end

          {subject, %{invitation: invitation, campaign: campaign}}
      end

    confirmation_url = "#{build_root_url()}/confirm?confirmation_token=#{token}"

    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject(subject)
    |> html_body(
      render_template(
        "confirmation_instructions.html",
        Map.merge(template_assigns, %{
          user: user,
          confirmation_url: confirmation_url
        })
      )
    )
  end

  @doc """
  Password reset instructions email with security notices.
  Includes both HTML and text versions.
  """
  def reset_password_instructions(user, token) do
    reset_url = "#{build_root_url()}/reset-password/#{token}"

    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Reset your Chi War password")
    |> header("X-Auto-Response-Suppress", "OOF")
    |> header("X-Mailer", "Chi War Mailer")
    |> html_body(
      render_template("reset_password_instructions.html", %{
        user: user,
        reset_url: reset_url
      })
    )
    |> text_body(
      render_template("reset_password_instructions.text", %{
        user: user,
        reset_url: reset_url
      })
    )
  end

  @doc """
  Notification email when user joins a campaign.
  """
  def joined_campaign(user, campaign) do
    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("You have joined the campaign: #{campaign.name}")
    |> html_body(
      render_template("joined_campaign.html", %{
        user: user,
        campaign: campaign
      })
    )
  end

  @doc """
  Notification email when user is removed from a campaign.
  """
  def removed_from_campaign(user, campaign) do
    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("You have been removed from the campaign: #{campaign.name}")
    |> html_body(
      render_template("removed_from_campaign.html", %{
        user: user,
        campaign: campaign
      })
    )
  end

  @doc """
  Notification email when AI provider credits are exhausted.
  Informs the user that AI image generation is temporarily unavailable.

  ## Parameters
    - user: The user to notify
    - campaign: The campaign affected
    - provider_name: The name of the AI provider (e.g., "Grok", "OpenAI")
  """
  def grok_credits_exhausted(user, campaign, provider_name \\ "Grok") do
    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("AI Image Generation Unavailable - #{provider_name} Credits Exhausted")
    |> html_body(
      render_template("grok_credits_exhausted.html", %{
        user: user,
        campaign: campaign,
        provider_name: provider_name
      })
    )
  end

  @doc """
  OTP login email with 6-digit code and magic link.
  Sent when user requests passwordless login.
  """
  def otp_login(user, otp_code, magic_token) do
    magic_link_url = "#{build_root_url()}/login/otp?token=#{magic_token}"

    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Your Chi War login code: #{otp_code}")
    |> header("X-Auto-Response-Suppress", "OOF")
    |> header("X-Mailer", "Chi War Mailer")
    |> html_body(
      render_template("otp_login.html", %{
        user: user,
        otp_code: otp_code,
        magic_link_url: magic_link_url
      })
    )
    |> text_body(
      render_template("otp_login.text", %{
        user: user,
        otp_code: otp_code,
        magic_link_url: magic_link_url
      })
    )
  end

  # Private helpers

  defp build_root_url do
    opts = Application.get_env(:shot_elixir, :mailer_url_options, [])
    scheme = opts[:scheme] || "https"
    host = opts[:host] || "chiwar.net"
    port = opts[:port]

    port_string = if port, do: ":#{port}", else: ""
    "#{scheme}://#{host}#{port_string}"
  end

  defp render_template(template_name, assigns) do
    Phoenix.View.render_to_string(
      EmailView,
      "user_email/#{template_name}",
      assigns
    )
  end
end
