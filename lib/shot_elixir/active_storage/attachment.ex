defmodule ShotElixir.ActiveStorage.Attachment do
  @moduledoc """
  Ecto schema for Rails ActiveStorage attachments table.
  Provides read-only access to polymorphic file associations stored by Rails.
  """
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "active_storage_attachments" do
    field :name, :string
    field :record_type, :string
    field :record_id, Ecto.UUID
    field :created_at, :utc_datetime

    belongs_to :blob, ShotElixir.ActiveStorage.Blob
  end
end
