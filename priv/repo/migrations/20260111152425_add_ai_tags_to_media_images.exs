defmodule ShotElixir.Repo.Migrations.AddAiTagsToMediaImages do
  use Ecto.Migration

  def change do
    alter table(:media_images) do
      # AI-generated tags from ImageKit (Google Vision / AWS Rekognition)
      # Format: [%{"name" => "warrior", "confidence" => 95.5, "source" => "google-auto-tagging"}, ...]
      add :ai_tags, {:array, :map}, default: []
    end

    # Index for searching by AI tags (GIN index for array contains queries)
    create index(:media_images, [:ai_tags], using: :gin)
  end
end
