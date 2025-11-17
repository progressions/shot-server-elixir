defmodule ShotElixir.ActiveStorage.Attachment do
  @moduledoc """
  Ecto schema for Rails ActiveStorage attachments table.
  Polymorphic associations between entities and uploaded files.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "active_storage_attachments" do
    field :name, :string
    field :record_type, :string
    field :record_id, Ecto.UUID
    field :created_at, :utc_datetime

    belongs_to :blob, ShotElixir.ActiveStorage.Blob
  end

  @doc """
  Changeset for creating a new attachment record.
  """
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:name, :record_type, :record_id, :blob_id, :created_at])
    |> validate_required([:name, :record_type, :record_id, :blob_id, :created_at])
    |> foreign_key_constraint(:blob_id)
    |> unique_constraint([:record_type, :record_id, :name],
      name: :index_active_storage_attachments_uniqueness
    )
  end
end
