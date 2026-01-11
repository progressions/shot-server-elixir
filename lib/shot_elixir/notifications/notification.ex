defmodule ShotElixir.Notifications.Notification do
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

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [:type, :title, :message, :payload, :read_at, :dismissed_at, :user_id])
    |> validate_required([:type, :title, :user_id])
  end
end
