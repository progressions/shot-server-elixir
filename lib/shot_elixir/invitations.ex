defmodule ShotElixir.Invitations do
  @moduledoc """
  The Invitations context for managing campaign invitations.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Invitations.Invitation
  alias ShotElixir.Accounts.User
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Campaigns.CampaignMembership

  def list_campaign_invitations(campaign_id) do
    query =
      from i in Invitation,
        where: i.campaign_id == ^campaign_id,
        preload: [:user, :pending_user, :campaign],
        order_by: [desc: i.created_at]

    Repo.all(query)
  end

  def get_invitation!(id) do
    Invitation
    |> preload([:user, :pending_user, :campaign])
    |> Repo.get!(id)
  end

  def get_invitation(id) do
    Invitation
    |> preload([:user, :pending_user, :campaign])
    |> Repo.get(id)
  end

  def create_invitation(attrs \\ %{}) do
    # Find pending user if exists
    pending_user =
      if attrs["email"] do
        User |> where([u], u.email == ^attrs["email"]) |> Repo.one()
      else
        nil
      end

    invitation_attrs =
      attrs
      |> Map.put("pending_user_id", pending_user && pending_user.id)

    %Invitation{}
    |> Invitation.changeset(invitation_attrs)
    |> Repo.insert()
  end

  def redeem_invitation(invitation, user_id) do
    # Check if user already in campaign
    existing_membership =
      from(cm in CampaignMembership,
        where: cm.campaign_id == ^invitation.campaign_id and cm.user_id == ^user_id
      )
      |> Repo.exists?()

    if existing_membership do
      {:error, :already_member}
    else
      Repo.transaction(fn ->
        # Add user to campaign using the schema
        %CampaignMembership{}
        |> CampaignMembership.changeset(%{
          campaign_id: invitation.campaign_id,
          user_id: user_id
        })
        |> Repo.insert!()

        # Mark invitation as redeemed
        invitation
        |> Invitation.changeset(%{
          "redeemed" => true,
          "redeemed_at" => DateTime.utc_now()
        })
        |> Repo.update!()

        # Return the campaign
        Campaign |> Repo.get!(invitation.campaign_id)
      end)
    end
  end

  def delete_invitation(invitation) do
    Repo.delete(invitation)
  end

  # Rate limiting functions
  @rate_limit_table :invitation_rate_limits

  # Initialize ETS table for rate limiting (called from application.ex)
  def init_rate_limiting do
    case :ets.whereis(@rate_limit_table) do
      :undefined ->
        :ets.new(@rate_limit_table, [:named_table, :public, :set, read_concurrency: true])

      _table ->
        :ok
    end
  end

  # Check if user can send invitations (max 10 per hour)
  def check_invitation_rate_limit(user_id) do
    check_rate_limit("invitation_#{user_id}", 10, 3600)
  end

  # Check if IP/email can register (max 5 attempts per hour per IP, 3 per email)
  def check_registration_rate_limit(ip_address, email) do
    with :ok <- check_rate_limit("registration_ip_#{ip_address}", 5, 3600),
         :ok <- check_rate_limit("registration_email_#{email}", 3, 3600) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Generic rate limit checker using sliding window
  defp check_rate_limit(key, max_attempts, window_seconds) do
    init_rate_limiting()
    now = System.system_time(:second)
    cutoff = now - window_seconds

    # Get existing attempts, filtering out expired ones
    attempts =
      case :ets.lookup(@rate_limit_table, key) do
        [{^key, timestamps}] ->
          Enum.filter(timestamps, &(&1 > cutoff))

        [] ->
          []
      end

    if length(attempts) >= max_attempts do
      {:error, :rate_limit_exceeded}
    else
      # Add current attempt
      new_attempts = [now | attempts]
      :ets.insert(@rate_limit_table, {key, new_attempts})
      :ok
    end
  end

  # Clean up expired rate limit entries (can be called periodically)
  def cleanup_rate_limits do
    init_rate_limiting()
    now = System.system_time(:second)

    :ets.foldl(
      fn {key, timestamps}, acc ->
        # Keep only timestamps from last 2 hours
        recent = Enum.filter(timestamps, &(&1 > now - 7200))

        if recent == [] do
          :ets.delete(@rate_limit_table, key)
        else
          :ets.insert(@rate_limit_table, {key, recent})
        end

        acc
      end,
      nil,
      @rate_limit_table
    )

    :ok
  end

  # Validation functions
  def valid_email_format?(email) when is_binary(email) do
    String.length(email) <= 254 and
      String.contains?(email, "@") and
      String.split(email, "@") |> length() == 2 and
      email =~ ~r/\A[^@\s]+@[^@.\s]+(?:\.[^@.\s]+)+\z/
  end

  def valid_email_format?(_), do: false

  def valid_password?(password) when is_binary(password) do
    String.length(password) >= 8 and
      password =~ ~r/[a-zA-Z]/ and
      password =~ ~r/[0-9]/
  end

  def valid_password?(_), do: false

  def sanitize_name_field(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.slice(0..49)
    |> strip_html_tags()
  end

  def sanitize_name_field(_), do: nil

  # Simple HTML tag stripper - removes anything between < and >
  defp strip_html_tags(text) do
    text
    |> String.replace(~r/<[^>]*>/, "")
    # Also strip HTML entities like &amp;
    |> String.replace(~r/&[^;]+;/, "")
    |> String.trim()
  end
end
