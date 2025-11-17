defmodule ShotElixir.ImageLoader do
  @moduledoc """
  Helper module for loading image URLs from ActiveStorage for any entity type.
  Provides reusable functions to populate image_url virtual fields.
  """

  alias ShotElixir.ActiveStorage

  @doc """
  Loads image URL for a single record.
  The record_type should match the Rails model name (e.g., "Character", "Vehicle").

  ## Examples

      iex> load_image_url(character, "Character")
      %Character{image_url: "https://..."}

      iex> load_image_url(vehicle, "Vehicle")
      %Vehicle{image_url: "https://..."}
  """
  def load_image_url(nil, _record_type), do: nil

  def load_image_url(record, record_type) when is_binary(record_type) do
    image_url = ActiveStorage.get_image_url(record_type, record.id)
    Map.put(record, :image_url, image_url)
  end

  @doc """
  Loads image URLs for a list of records efficiently (single query).

  ## Examples

      iex> load_image_urls([char1, char2, char3], "Character")
      [%Character{image_url: "..."}, %Character{image_url: nil}, ...]
  """
  def load_image_urls([], _record_type), do: []

  def load_image_urls(records, record_type) when is_list(records) and is_binary(record_type) do
    record_ids = Enum.map(records, & &1.id)
    image_urls = ActiveStorage.get_image_urls_for_records(record_type, record_ids)

    Enum.map(records, fn record ->
      Map.put(record, :image_url, Map.get(image_urls, record.id))
    end)
  end
end
