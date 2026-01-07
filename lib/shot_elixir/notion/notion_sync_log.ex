defmodule ShotElixir.Notion.NotionSyncLog do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notion_sync_logs" do
    field :status, :string
    field :payload, :map, default: %{}
    field :response, :map, default: %{}
    field :error_message, :string

    belongs_to :character, ShotElixir.Characters.Character

    timestamps(inserted_at: :created_at, updated_at: :updated_at, type: :utc_datetime)
  end

  def changeset(notion_sync_log, attrs) do
    notion_sync_log
    |> cast(attrs, [:status, :payload, :response, :error_message, :character_id])
    |> validate_required([:status, :character_id])
    |> validate_inclusion(:status, ["success", "error"])
    |> foreign_key_constraint(:character_id)
  end
end
