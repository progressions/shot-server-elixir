defmodule ShotElixir.Repo.Migrations.CreateAiGeneratedImages do
  use Ecto.Migration

  def change do
    create table(:ai_generated_images, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")
      add :campaign_id, references(:campaigns, type: :uuid, on_delete: :delete_all), null: false
      add :entity_type, :string
      add :entity_id, :uuid
      add :status, :string, null: false, default: "orphan"
      add :imagekit_file_id, :string, null: false
      add :imagekit_url, :string, null: false
      add :imagekit_file_path, :string
      add :filename, :string
      add :content_type, :string, default: "image/jpeg"
      add :byte_size, :integer
      add :width, :integer
      add :height, :integer
      add :prompt, :text
      add :ai_provider, :string
      add :generated_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:ai_generated_images, [:campaign_id])
    create index(:ai_generated_images, [:entity_type, :entity_id])
    create index(:ai_generated_images, [:status])
    create unique_index(:ai_generated_images, [:imagekit_file_id])
  end
end
