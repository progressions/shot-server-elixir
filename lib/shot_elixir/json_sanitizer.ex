defmodule ShotElixir.JsonSanitizer do
  @moduledoc """
  Recursively coerces data structures so they are safe to encode as JSON.
  - 16-byte Postgres UUID binaries become standard UUID strings.
  - DateTime / NaiveDateTime values are converted to ISO-8601 strings.
  - Lists and maps are sanitized deeply while preserving keys.
  """

  alias Ecto.UUID

  def sanitize(%DateTime{} = value), do: DateTime.to_iso8601(value)
  def sanitize(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  def sanitize(%Decimal{} = value), do: Decimal.to_string(value)
  def sanitize(%Ecto.Association.NotLoaded{}), do: nil

  def sanitize(%_struct{} = value) do
    value
    |> Map.from_struct()
    |> Map.delete(:__meta__)
    |> sanitize()
  end

  def sanitize(value) when is_binary(value) do
    cond do
      # Only treat as UUID if it's 16 bytes AND not printable text
      byte_size(value) == 16 and not String.printable?(value) -> normalize_uuid(value)
      String.valid?(value) -> value
      true -> normalize_uuid(value)
    end
  end

  def sanitize(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, val}, acc ->
      Map.put(acc, key, sanitize(val))
    end)
  end

  def sanitize(value) when is_list(value) do
    Enum.map(value, &sanitize/1)
  end

  def sanitize(value), do: value

  defp normalize_uuid(nil), do: nil

  defp normalize_uuid(value) when is_binary(value) and byte_size(value) == 16 do
    case UUID.load(value) do
      {:ok, uuid} -> uuid
      :error -> Base.encode16(value, case: :lower)
    end
  end

  defp normalize_uuid(value), do: value
end
