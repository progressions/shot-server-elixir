defmodule ShotElixirWeb.Api.V2.InvitationView do
  def render("index.json", %{invitations: invitations}) do
    Enum.map(invitations, &render_invitation_index/1)
  end

  def render("show.json", %{invitation: invitation}) do
    render_invitation_detail(invitation)
  end

  def render("redeem.json", %{campaign: campaign, message: message}) do
    %{
      campaign: render_campaign_basic(campaign),
      message: message
    }
  end

  def render("register.json", %{
        user: user,
        message: message,
        requires_confirmation: requires_confirmation
      }) do
    %{
      message: message,
      requires_confirmation: requires_confirmation,
      user: %{
        id: user.id,
        email: user.email,
        first_name: user.first_name,
        last_name: user.last_name
      }
    }
  end

  def render("error.json", %{changeset: changeset}) do
    %{errors: translate_errors(changeset)}
  end

  def render("error.json", %{error: error}) do
    %{error: error}
  end

  def render("error.json", %{error: error, field: field}) do
    %{error: error, field: field}
  end

  def render("mismatch.json", %{
        error: error,
        current_user_email: current_email,
        invitation_email: invitation_email
      }) do
    %{
      error: error,
      current_user_email: current_email,
      invitation_email: invitation_email,
      mismatch: true
    }
  end

  def render("already_member.json", %{error: error, campaign: campaign}) do
    %{
      error: error,
      already_member: true,
      campaign: render_campaign_basic(campaign)
    }
  end

  def render("rate_limit.json", %{error: error, retry_after: retry_after}) do
    %{
      error: error,
      retry_after: retry_after
    }
  end

  defp render_invitation_index(invitation) do
    base = %{
      id: invitation.id,
      email: invitation.email,
      redeemed: invitation.redeemed,
      redeemed_at: invitation.redeemed_at,
      created_at: invitation.created_at,
      updated_at: invitation.updated_at,
      entity_class: "Invitation"
    }

    # Add associations if loaded
    base
    |> add_if_loaded(:user, invitation.user)
    |> add_if_loaded(:pending_user, invitation.pending_user)
    |> add_if_loaded(:campaign, invitation.campaign)
  end

  defp render_invitation_detail(invitation) do
    base = %{
      id: invitation.id,
      email: invitation.email,
      redeemed: invitation.redeemed,
      redeemed_at: invitation.redeemed_at,
      created_at: invitation.created_at,
      updated_at: invitation.updated_at,
      entity_class: "Invitation"
    }

    # Add associations if loaded
    base
    |> add_if_loaded(:user, invitation.user)
    |> add_if_loaded(:pending_user, invitation.pending_user)
    |> add_if_loaded(:campaign, invitation.campaign)
  end

  defp add_if_loaded(base, key, association) do
    if Ecto.assoc_loaded?(association) do
      Map.put(base, key, render_association(key, association))
    else
      base
    end
  end

  defp render_association(:user, nil), do: nil

  defp render_association(:user, user) do
    %{
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name
    }
  end

  defp render_association(:pending_user, nil), do: nil

  defp render_association(:pending_user, user) do
    %{
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name
    }
  end

  defp render_association(:campaign, nil), do: nil

  defp render_association(:campaign, campaign) do
    render_campaign_basic(campaign)
  end

  defp render_association(_, association), do: association

  defp render_campaign_basic(campaign) do
    %{
      id: campaign.id,
      name: campaign.name,
      description: campaign.description
    }
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
