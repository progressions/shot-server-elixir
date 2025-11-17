defmodule ShotElixir.ActiveStorage.Blob do
  @moduledoc """
  Ecto schema for Rails ActiveStorage blobs table.
  Stores file metadata for uploaded images.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime]

  schema "active_storage_blobs" do
    field :key, :string
    field :filename, :string
    field :content_type, :string
    # Rails stores this as text (JSON string), we need to decode it
    field :metadata, :string
    field :service_name, :string
    field :byte_size, :integer
    field :checksum, :string
    field :created_at, :utc_datetime
  end

  @doc """
  Changeset for creating a new blob record.
  """
  def changeset(blob, attrs) do
    blob
    |> cast(attrs, [:key, :filename, :content_type, :metadata, :service_name, :byte_size, :checksum, :created_at])
    |> validate_required([:key, :filename, :content_type, :service_name, :created_at])
    |> unique_constraint(:key)
  end

  @doc """
  Returns the metadata as a decoded map.
  Rails stores metadata as a JSON string, so we need to parse it.
  """
  def decoded_metadata(%__MODULE__{metadata: nil}), do: %{}
  def decoded_metadata(%__MODULE__{metadata: ""}), do: %{}

  def decoded_metadata(%__MODULE__{metadata: metadata}) when is_binary(metadata) do
    case Jason.decode(metadata) do
      {:ok, decoded} -> decoded
      {:error, _} -> %{}
    end
  end

  def decoded_metadata(%__MODULE__{metadata: metadata}) when is_map(metadata), do: metadata
  def decoded_metadata(_), do: %{}
end
