defmodule ShotElixir.Slug do
  @moduledoc """
  Utilities for working with slug+UUID identifiers.

  - `extract_uuid/1` pulls the UUID out of either a bare UUID or a "slug-uuid" string.
  - `slugify_name/1` converts a name to a URL-safe slug (lowercase, hyphenated, ASCII-safe).
  - `slugged_id/2` combines a slugified name with a UUID when a slug is available.
  """

  @uuid_regex ~r/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$/

  @spec extract_uuid(String.t()) :: String.t()
  def extract_uuid(id_or_slug) when is_binary(id_or_slug) do
    case Regex.run(@uuid_regex, id_or_slug) do
      [_, candidate] ->
        case Ecto.UUID.cast(candidate) do
          {:ok, uuid} -> uuid
          :error -> id_or_slug
        end

      _ ->
        id_or_slug
    end
  end

  def extract_uuid(other), do: other

  @spec slugify_name(String.t() | nil) :: String.t()
  def slugify_name(nil), do: ""

  def slugify_name(name) do
    name
    |> String.downcase()
    |> String.normalize(:nfd)
    |> String.replace(~r/[^a-z0-9\s-]/u, "")
    |> String.replace(~r/[\s_-]+/, "-")
    |> String.trim("-")
  end

  @spec slugged_id(String.t() | nil, String.t()) :: String.t()
  def slugged_id(name, id) when is_binary(id) do
    slug = slugify_name(name)

    if slug == "" do
      id
    else
      slug <> "-" <> id
    end
  end
end
