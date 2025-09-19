defmodule ShotElixir.Uploaders.ImageUploader do
  @moduledoc """
  Arc uploader definition for handling image uploads to ImageKit.
  Validates file types and delegates storage to ImageKit service.
  """

  use Arc.Definition
  use Arc.Ecto.Definition

  alias ShotElixir.Services.ImagekitService

  @versions [:original, :thumb, :medium]
  @extension_whitelist ~w(.jpg .jpeg .gif .png .webp .svg)
  @max_file_size 10_485_760 # 10MB in bytes

  @doc """
  Validates uploaded files for acceptable extensions and size.
  """
  def validate({file, _scope}) do
    with :ok <- validate_extension(file),
         :ok <- validate_file_size(file) do
      true
    else
      {:error, _reason} -> false
    end
  end

  @doc """
  Define transformations for different versions.
  Since ImageKit handles transformations via URL parameters,
  we'll store version metadata but not create actual versions.
  """
  def transform(:thumb, _) do
    # ImageKit will handle this via URL parameters
    {:noaction}
  end

  def transform(:medium, _) do
    # ImageKit will handle this via URL parameters
    {:noaction}
  end

  @doc """
  Override storage to use ImageKit instead of local/S3.
  """
  def store({%{file_name: file_name, path: path} = _file, scope}) do
    folder = folder_for_scope(scope)
    tags = tags_for_scope(scope)

    case ImagekitService.upload_file(path, %{
      file_name: file_name,
      folder: folder,
      tags: tags
    }) do
      {:ok, response} ->
        # Return the ImageKit file name for Arc to store
        {:ok, response.name}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate URL for the stored file.
  This will be called by Arc when accessing the file.
  """
  def url({file_name, _scope}, version \\ :original) do
    transformations = transformations_for_version(version)
    ImagekitService.generate_url(file_name, transformations)
  end

  @doc """
  Delete file from ImageKit when record is deleted.
  """
  def delete({_file_name, _scope}) do
    # Extract file_id if stored in metadata
    # For now, we'll skip deletion as ImageKit doesn't provide easy lookup by name
    :ok
  end

  # Private functions

  defp validate_extension(file) do
    file_extension =
      file.file_name
      |> Path.extname()
      |> String.downcase()

    if file_extension in @extension_whitelist do
      :ok
    else
      {:error, "Invalid file type"}
    end
  end

  defp validate_file_size(file) do
    case File.stat(file.path) do
      {:ok, %{size: size}} when size <= @max_file_size ->
        :ok

      {:ok, %{size: size}} ->
        {:error, "File too large: #{size} bytes (max: #{@max_file_size})"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp folder_for_scope(scope) when is_map(scope) do
    case scope do
      %{__struct__: module} ->
        module
        |> Module.split()
        |> List.last()
        |> Macro.underscore()
        |> then(&"/#{&1}s")

      _ ->
        "/uploads"
    end
  end

  defp folder_for_scope(_), do: "/uploads"

  defp tags_for_scope(scope) when is_map(scope) do
    case scope do
      %{__struct__: module} ->
        [module |> to_string() |> String.split(".") |> List.last()]

      _ ->
        []
    end
  end

  defp tags_for_scope(_), do: []

  defp transformations_for_version(:thumb) do
    [%{height: 150, width: 150, crop: "at_max"}]
  end

  defp transformations_for_version(:medium) do
    [%{height: 500, width: 500, crop: "at_max"}]
  end

  defp transformations_for_version(_), do: []
end