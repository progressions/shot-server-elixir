defmodule ShotElixir.Accounts.CliSession do
  @moduledoc """
  Schema for tracking CLI authentication sessions.

  Records are created when a CLI authorization code is approved and a token is issued.
  Used to display active CLI connections on the user's profile page.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ShotElixir.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cli_sessions" do
    field :ip_address, :string
    field :user_agent, :string
    field :last_seen_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cli_session, attrs) do
    cli_session
    |> cast(attrs, [:ip_address, :user_agent, :last_seen_at, :user_id])
    |> validate_required([:user_id])
  end
end
