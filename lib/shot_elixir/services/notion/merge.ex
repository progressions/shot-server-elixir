defmodule ShotElixir.Services.Notion.Merge do
  @moduledoc """
  Helpers for smart merging Notion values with Chi War data.
  """

  @doc """
  Smart merge for action_values - handles 0 as blank.
  """
  def smart_merge_action_values(local, notion) do
    all_keys =
      MapSet.union(
        MapSet.new(Map.keys(local)),
        MapSet.new(Map.keys(notion))
      )

    Enum.reduce(all_keys, %{}, fn key, acc ->
      local_val = Map.get(local, key)
      notion_val = Map.get(notion, key)

      merged_val = smart_merge_value(local_val, notion_val, action_value?: true)
      Map.put(acc, key, merged_val)
    end)
  end

  @doc """
  Smart merge for description - handles empty strings as blank.
  """
  def smart_merge_description(local, notion) do
    all_keys =
      MapSet.union(
        MapSet.new(Map.keys(local)),
        MapSet.new(Map.keys(notion))
      )

    Enum.reduce(all_keys, %{}, fn key, acc ->
      local_val = Map.get(local, key)
      notion_val = Map.get(notion, key)

      merged_val = smart_merge_value(local_val, notion_val, action_value?: false)
      Map.put(acc, key, merged_val)
    end)
  end

  @doc """
  Core merge logic for a single value.

  Rules:
  - If both blank → keep local (nil)
  - If local blank, notion has value → use notion
  - If notion blank, local has value → keep local
  - If both have values → keep local (don't overwrite)
  """
  def smart_merge_value(local_val, notion_val, opts \\ []) do
    is_action_value = Keyword.get(opts, :action_value?, false)
    local_blank = blank?(local_val, is_action_value)
    notion_blank = blank?(notion_val, is_action_value)

    cond do
      local_blank and notion_blank -> local_val
      local_blank and not notion_blank -> notion_val
      not local_blank and notion_blank -> local_val
      # Both have values - keep local (no overwrite)
      true -> local_val
    end
  end

  @doc """
  Check if a value is considered "blank".

  For action values: nil, "", or 0 are blank.
  For other values: nil or "" are blank.
  """
  def blank?(value, is_action_value \\ false)
  def blank?(nil, _), do: true
  def blank?("", _), do: true
  def blank?(0, true), do: true
  def blank?("0", true), do: true
  def blank?(value, true) when is_float(value) and value == 0.0, do: true
  def blank?(_, _), do: false
end
