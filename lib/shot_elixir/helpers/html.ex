defmodule ShotElixir.Helpers.Html do
  @moduledoc """
  HTML utility functions for text processing.

  Provides functions to sanitize and convert HTML content to plain text,
  primarily used when syncing data to external services like Notion.
  """

  @doc """
  Strips HTML tags from text, converting paragraph and line breaks to newlines.

  This function is designed to convert rich text content (HTML) to plain text
  suitable for Notion's rich_text property format.

  ## Examples

      iex> ShotElixir.Helpers.Html.strip_html("<p>Hello</p><p>World</p>")
      "Hello\\nWorld"

      iex> ShotElixir.Helpers.Html.strip_html("Line one<br>Line two")
      "Line one\\nLine two"

      iex> ShotElixir.Helpers.Html.strip_html("<strong>Bold</strong> text")
      "Bold text"

      iex> ShotElixir.Helpers.Html.strip_html(nil)
      ""

  """
  @spec strip_html(binary() | nil) :: binary()
  def strip_html(text) when is_binary(text) do
    text
    |> String.replace(~r/<p>/, "")
    |> String.replace(~r/<\/p>/, "\n")
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<[^>]+>/, "")
    |> String.trim()
  end

  def strip_html(_), do: ""
end
