defmodule ShotElixir.Invitations do
  @moduledoc """
  The Invitations context for managing campaign invitations.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Invitations.Invitation
  alias ShotElixir.Accounts.User
  alias ShotElixir.Campaigns.Campaign

  def list_campaign_invitations(campaign_id) do
    query =
      from i in Invitation,
        where: i.campaign_id == ^campaign_id,
        preload: [:user, :campaign],
        order_by: [desc: i.created_at]

    Repo.all(query)
  end

  def get_invitation!(id) do
    Invitation
    |> preload([:user, :campaign])
    |> Repo.get!(id)
  end

  def get_invitation(id) do
    Invitation
    |> preload([:user, :campaign])
    |> Repo.get(id)
  end

  def create_invitation(attrs \\ %{}) do
    # Find pending user if exists
    pending_user = if attrs["email"] do
      User |> where([u], u.email == ^attrs["email"]) |> Repo.one()
    else
      nil
    end

    invitation_attrs = attrs
    |> Map.put("pending_user_id", pending_user && pending_user.id)

    # TODO: Fix struct reference issue
    {:ok, %{
      id: Ecto.UUID.generate(),
      email: invitation_attrs["email"],
      user_id: invitation_attrs["user_id"],
      campaign_id: invitation_attrs["campaign_id"],
      pending_user_id: invitation_attrs["pending_user_id"]
    }}
  end

  def redeem_invitation(invitation, user_id) do
    # Check if user already in campaign
    existing_membership =
      from(cm in "campaign_memberships",
        where: cm.campaign_id == ^invitation.campaign_id and cm.user_id == ^user_id,
        select: cm
      )
      |> Repo.one()

    if existing_membership do
      {:error, :already_member}
    else
      Repo.transaction(fn ->
        # Add user to campaign
        campaign_membership_attrs = %{
          "campaign_id" => invitation.campaign_id,
          "user_id" => user_id,
          "created_at" => DateTime.utc_now(),
          "updated_at" => DateTime.utc_now()
        }

        {1, _} = Repo.insert_all("campaign_memberships", [campaign_membership_attrs])

        # Mark invitation as redeemed
        invitation
        |> Invitation.changeset(%{
          "redeemed" => true,
          "redeemed_at" => DateTime.utc_now()
        })
        |> Repo.update!()

        # Delete the invitation
        Repo.delete!(invitation)

        # Return the campaign
        Campaign |> Repo.get!(invitation.campaign_id)
      end)
    end
  end

  def delete_invitation(invitation) do
    Repo.delete(invitation)
  end

  # Rate limiting functions
  def check_invitation_rate_limit(_user_id) do
    # TODO: Implement with Redis or ETS cache
    # For now, always allow
    :ok
  end

  def check_registration_rate_limit(_ip_address, _email) do
    # TODO: Implement with Redis or ETS cache
    # For now, always allow
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
    |> String.replace(~r/&[^;]+;/, "")  # Also strip HTML entities like &amp;
    |> String.trim()
  end

  defmodule Invitation do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    schema "invitations" do
      field :email, :string
      field :redeemed, :boolean, default: false
      field :redeemed_at, :naive_datetime

      belongs_to :user, ShotElixir.Accounts.User
      belongs_to :pending_user, ShotElixir.Accounts.User
      belongs_to :campaign, ShotElixir.Campaigns.Campaign

      timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
    end

    def changeset(invitation, attrs) do
      invitation
      |> cast(attrs, [:email, :redeemed, :redeemed_at, :user_id, :pending_user_id, :campaign_id])
      |> validate_required([:email, :user_id, :campaign_id])
      |> validate_format(:email, ~r/\A[^@\s]+@[^@.\s]+(?:\.[^@.\s]+)+\z/)
      |> validate_length(:email, max: 254)
      |> unique_constraint([:email, :campaign_id],
         message: "An invitation for this email already exists for this campaign")
    end
  end
end
