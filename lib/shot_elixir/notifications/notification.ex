defmodule ShotElixir.Notifications.Notification do
  @moduledoc """
  Ecto schema representing a user-facing notification within the ShotElixir
  application.

  Notifications are used to inform users about important events in the
  system, such as AI credit exhaustion, campaign invitations, or system messages.

  ## Key fields

    * `type` - a short string that classifies the notification (for example,
      "ai_credits_exhausted"). The application logic can use this to determine
      how to render or handle the notification.

    * `payload` - a free-form map that stores structured metadata for the
      notification (such as related resource IDs or other context needed by
      clients). This is not intended for user-facing copy, but for programmatic use.

    * `read_at` - the UTC datetime when the notification was marked as read
      by the user. A `nil` value means the notification has not yet been read.

    * `dismissed_at` - the UTC datetime when the notification was dismissed
      (cleared/hidden) by the user. A `nil` value means the notification is
      still active.

  Each notification belongs to a user and uses UUID primary keys and UTC
  timestamps, consistent with other schemas in this application.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notifications" do
    field :type, :string
    field :title, :string
    field :message, :string
    field :payload, :map, default: %{}
    field :read_at, :utc_datetime
    field :dismissed_at, :utc_datetime

    belongs_to :user, ShotElixir.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new notification. Includes user_id assignment.
  """
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:type, :title, :message, :payload, :read_at, :dismissed_at, :user_id])
    |> validate_required([:type, :title, :user_id])
  end

  @doc """
  Changeset for user updates. Only allows updating read_at and dismissed_at
  to prevent users from modifying notification content or ownership.
  """
  def update_changeset(notification, attrs) do
    notification
    |> cast(attrs, [:read_at, :dismissed_at])
  end
end
