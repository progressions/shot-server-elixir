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
    |> text_body(render_text_template("welcome.text", %{user: user}))
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
    |> text_body(
      render_text_template("invitation.text", %{
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
    |> text_body(
      render_text_template(
        "confirmation_instructions.text",
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
      render_text_template("reset_password_instructions.text", %{
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
    |> text_body(
      render_text_template("joined_campaign.text", %{
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
    |> text_body(
      render_text_template("removed_from_campaign.text", %{
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
  def ai_credits_exhausted(user, campaign, provider_name \\ "Unknown") do
    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("AI Image Generation Unavailable - #{provider_name} Credits Exhausted")
    |> html_body(
      render_template("ai_credits_exhausted.html", %{
        user: user,
        campaign: campaign,
        provider_name: provider_name
      })
    )
    |> text_body(
      render_text_template("ai_credits_exhausted.text", %{
        user: user,
        campaign: campaign,
        provider_name: provider_name
      })
    )
  end

  @doc """
  Notification email when Notion integration status changes.

  ## Parameters
    - user: The campaign owner to notify
    - campaign: The campaign affected
    - new_status: The new status ("working", "needs_attention", "disconnected")
  """
  def notion_status_changed(user, campaign, new_status) do
    subject =
      case new_status do
        "working" -> "Notion Integration Connected - #{campaign.name}"
        "needs_attention" -> "Notion Integration Needs Attention - #{campaign.name}"
        "disconnected" -> "Notion Integration Disconnected - #{campaign.name}"
        _ -> "Notion Integration Status Update - #{campaign.name}"
      end

    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject(subject)
    |> html_body(
      render_template("notion_status_changed.html", %{
        user: user,
        campaign: campaign,
        new_status: new_status
      })
    )
    |> text_body(
      render_text_template("notion_status_changed.text", %{
        user: user,
        campaign: campaign,
        new_status: new_status
      })
    )
  end

  @doc """
  Notification email when user links their Discord account.

  ## Parameters
    - user: The user who linked their Discord account
    - discord_username: The Discord username that was linked
  """
  def discord_linked(user, discord_username) do
    profile_url = "#{build_root_url()}/profile"

    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Discord Account Linked - #{discord_username}")
    |> html_body(
      render_template("discord_linked.html", %{
        user: user,
        discord_username: discord_username,
        profile_url: profile_url
      })
    )
    |> text_body(
      render_text_template("discord_linked.text", %{
        user: user,
        discord_username: discord_username,
        profile_url: profile_url
      })
    )
  end

  @doc """
  Notification email when user unlinks their Discord account.

  ## Parameters
    - user: The user who unlinked their Discord account
    - discord_username: The Discord username that was unlinked
  """
  def discord_unlinked(user, discord_username) do
    profile_url = "#{build_root_url()}/profile"

    new()
    |> to({user.first_name || user.email, user.email})
    |> from({@from_name, @from_email})
    |> subject("Discord Account Unlinked")
    |> html_body(
      render_template("discord_unlinked.html", %{
        user: user,
        discord_username: discord_username,
        profile_url: profile_url
      })
    )
    |> text_body(
      render_text_template("discord_unlinked.text", %{
        user: user,
        discord_username: discord_username,
        profile_url: profile_url
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
      render_text_template("otp_login.text", %{
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

  # Renders an HTML email template wrapped in the shared layout
  defp render_template(template_name, assigns) do
    EmailView.render_with_layout("user_email/#{template_name}", assigns)
  end

  # Renders a plain text email template (no layout wrapper)
  defp render_text_template(template_name, assigns) do
    Phoenix.View.render_to_string(
      EmailView,
      "user_email/#{template_name}",
      assigns
    )
  end
end
