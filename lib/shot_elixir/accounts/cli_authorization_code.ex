defmodule ShotElixir.Accounts.CliAuthorizationCode do
  @moduledoc """
  Schema for CLI device authorization codes.

  Used for the OAuth-style device flow where:
  1. CLI requests a code via /api/v2/cli/auth/start
  2. User approves in browser at /cli/auth?code=XXX
  3. CLI polls /api/v2/cli/auth/poll until approved
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias ShotElixir.Accounts.User

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cli_authorization_codes" do
    field :code, :string
    field :approved, :boolean, default: false
    field :expires_at, :utc_datetime

    belongs_to :user, User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(cli_auth_code, attrs) do
    cli_auth_code
    |> cast(attrs, [:code, :approved, :expires_at, :user_id])
    |> validate_required([:code, :expires_at])
    |> unique_constraint(:code)
  end

  @doc """
  Checks if the code has expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now()) == :lt
  end
end
