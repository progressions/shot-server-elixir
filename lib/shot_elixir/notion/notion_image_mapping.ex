defmodule ShotElixir.Notion.NotionImageMapping do
  @moduledoc """
  Maps Notion image blocks to ImageKit uploads to prevent duplicate imports.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notion_image_mappings" do
    field :notion_page_id, :string
    field :notion_block_id, :string
    field :imagekit_file_id, :string
    field :imagekit_url, :string
    field :imagekit_file_path, :string

    timestamps(type: :utc_datetime)
  end

  def changeset(mapping, attrs) do
    mapping
    |> cast(attrs, [
      :notion_page_id,
      :notion_block_id,
      :imagekit_file_id,
      :imagekit_url,
      :imagekit_file_path
    ])
    |> validate_required([:notion_page_id, :notion_block_id, :imagekit_file_id, :imagekit_url])
    |> unique_constraint(:notion_block_id, name: :notion_image_mappings_page_block_index)
  end
end
