defmodule ShotElixir.Models.Concerns.WithImagekit do
  @moduledoc """
  Concern for adding ImageKit image handling to Ecto schemas.
  Provides image upload, URL generation, and caching functionality
  compatible with the Rails WithImagekit concern.
  """

  defmacro __using__(_opts) do
    quote do
      use Arc.Ecto.Schema
      import ShotElixir.Models.Concerns.WithImagekit
      import Ecto.Schema

      alias ShotElixir.Uploaders.ImageUploader
      alias ShotElixir.Services.ImagekitService
      alias ShotElixir.Repo

      # Add Arc.Ecto attachment field
      # This creates :image field and :image_url virtual field
      field :image, ImageUploader.Type
      field :image_url, :string, virtual: true
      field :image_data, :map, default: %{}

      @doc """
      Uploads an image for this record using ImageKit.
      """
      def upload_image(%__MODULE__{} = record, %Plug.Upload{} = upload) do
        changeset =
          record
          |> Ecto.Changeset.change()
          |> ImageUploader.cast_attachments(%{image: upload})

        case Repo.update(changeset) do
          {:ok, updated_record} ->
            # Store ImageKit metadata if available
            if upload_response = get_upload_metadata(upload) do
              store_image_metadata(updated_record, upload_response)
            else
              {:ok, updated_record}
            end

          error ->
            error
        end
      end

      @doc """
      Returns the image URL, using cache if available.
      """
      def image_url(%__MODULE__{} = record) do
        cond do
          # First check virtual field (already loaded)
          record.image_url != nil ->
            record.image_url

          # Then check Arc attachment
          record.image != nil ->
            ImageUploader.url({record.image, record})

          # Finally check legacy image_data for Rails compatibility
          map_size(record.image_data) > 0 ->
            ImagekitService.generate_url_from_metadata(record.image_data)

          true ->
            nil
        end
      end

      @doc """
      Clears the image URL cache for this record.
      """
      def clear_image_cache(%__MODULE__{} = record) do
        cache_key = image_cache_key(record)
        Cachex.del(:image_cache, cache_key)
        record
      end

      # Public function to load image URL
      def with_image_url(%__MODULE__{} = record) do
        url = get_cached_image_url(record)
        %{record | image_url: url}
      end

      # Private functions

      defp get_cached_image_url(%__MODULE__{} = record) do
        cache_key = image_cache_key(record)

        case Cachex.fetch(:image_cache, cache_key) do
          {:ok, url} ->
            url

          {:commit, url} ->
            url

          _ ->
            # Cache miss, generate URL
            url = generate_image_url(record)

            if url do
              # Cache for 1 hour (matching Rails implementation)
              Cachex.put(:image_cache, cache_key, url, ttl: :timer.hours(1))
            end

            url
        end
      end

      defp generate_image_url(%__MODULE__{} = record) do
        cond do
          # Arc attachment
          record.image != nil ->
            ImageUploader.url({record.image, record})

          # Legacy image_data (Rails compatibility)
          map_size(record.image_data) > 0 ->
            ImagekitService.generate_url_from_metadata(record.image_data)

          true ->
            nil
        end
      end

      defp image_cache_key(%__MODULE__{} = record) do
        "image_url:#{__MODULE__}:#{record.id}:#{record.updated_at}"
      end

      defp get_upload_metadata(%Plug.Upload{path: path, filename: filename}) do
        # This would be populated by the ImageUploader after successful upload
        # For now, return nil as metadata is handled internally by Arc
        nil
      end

      defp store_image_metadata(%__MODULE__{} = record, metadata) do
        changeset =
          record
          |> Ecto.Changeset.change()
          |> Ecto.Changeset.put_change(:image_data, metadata)

        Repo.update(changeset)
      end

      # Override Arc's default delete behavior
      def delete_image(%__MODULE__{} = record) do
        if record.image do
          ImageUploader.delete({record.image, record})

          changeset =
            record
            |> Ecto.Changeset.change()
            |> Ecto.Changeset.put_change(:image, nil)
            |> Ecto.Changeset.put_change(:image_data, %{})

          Repo.update(changeset)
        else
          {:ok, record}
        end
      end

      # Make functions overridable
      defoverridable [
        upload_image: 2,
        image_url: 1,
        clear_image_cache: 1,
        delete_image: 1,
        with_image_url: 1
      ]
    end
  end
end