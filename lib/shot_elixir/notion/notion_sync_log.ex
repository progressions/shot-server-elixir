defmodule ShotElixir.Notion.NotionSyncLog do
  use Ecto.Schema
  import Ecto.Changeset

  @entity_types ~w(character site party faction juncture adventure)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notion_sync_logs" do
    field :status, :string
    field :payload, :map, default: %{}
    field :response, :map, default: %{}
    field :error_message, :string
    field :entity_type, :string
    field :entity_id, :binary_id

    belongs_to :character, ShotElixir.Characters.Character

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(notion_sync_log, attrs) do
    notion_sync_log
    |> cast(attrs, [
      :status,
      :payload,
      :response,
      :error_message,
      :entity_type,
      :entity_id,
      :character_id
    ])
    |> validate_required([:status, :entity_type, :entity_id])
    |> validate_inclusion(:status, ["success", "error"])
    |> validate_inclusion(:entity_type, @entity_types)
    |> foreign_key_constraint(:character_id)
  end
end
