defmodule ShotElixir.Repo.Migrations.CreateMediaImages do
  use Ecto.Migration

  def change do
    create table(:media_images, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :campaign_id, references(:campaigns, type: :uuid, on_delete: :delete_all), null: false

      # Source tracking: "upload" or "ai_generated"
      add :source, :string, null: false

      # Entity attachment (optional - nil if orphan)
      add :entity_type, :string
      add :entity_id, :uuid
      add :status, :string, null: false, default: "orphan"

      # Link to ActiveStorage blob (for images that are attached to entities)
      # This allows us to find the media_image from an ActiveStorage attachment
      add :active_storage_blob_id, :bigint

      # ImageKit data (always present)
      add :imagekit_file_id, :string, null: false
      add :imagekit_url, :string, null: false
      add :imagekit_file_path, :string

      # File metadata
      add :filename, :string
      add :content_type, :string, default: "image/jpeg"
      add :byte_size, :integer
      add :width, :integer
      add :height, :integer

      # AI-specific metadata (optional, only for AI-generated images)
      add :prompt, :text
      add :ai_provider, :string
      add :generated_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      # Upload tracking (for manually uploaded images)
      add :uploaded_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:media_images, [:campaign_id])
    create index(:media_images, [:entity_type, :entity_id])
    create index(:media_images, [:status])
    create index(:media_images, [:source])
    create index(:media_images, [:active_storage_blob_id])
    create unique_index(:media_images, [:imagekit_file_id])
  end
end
