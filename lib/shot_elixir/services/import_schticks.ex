defmodule ShotElixir.Services.ImportSchticks do
  @moduledoc """
  Service for importing schticks from YAML data.
  Mirrors the Rails ImportSchticks service.
  """

  alias ShotElixir.Repo
  alias ShotElixir.Schticks.Schtick
  import Ecto.Query

  @roman_numerals ["I", "II", "III", "IV", "V"]

  @colors %{
    "Guns" => "#b71c1c",
    "Martial Arts" => "#4a148c",
    "Driving" => "#311b92",
    "Sorcery" => "#0d47a1",
    "Creature" => "#006064",
    "Transformed Animal" => "#1b5e20",
    "Gene Freak" => "#9e9d24",
    "Cyborg" => "#ff8f00",
    "Foe" => "#bf360c",
    "Core" => "#3e2723"
  }

  @doc """
  Import schticks from parsed YAML data.

  ## Parameters
    - data: List of category maps from parsed YAML
    - campaign: The campaign to import schticks into

  ## Returns
    - {:ok, count} on success with number of schticks imported
    - {:error, reason} on failure
  """
  def call(data, campaign) when is_list(data) do
    results =
      Enum.flat_map(data, fn category ->
        parse_category(category, campaign)
      end)

    successful = Enum.count(results, fn result -> match?({:ok, _}, result) end)
    {:ok, successful}
  end

  def call(_, _), do: {:error, "Invalid data format - expected a list"}

  defp parse_category(category, campaign) do
    paths = category["paths"] || []

    Enum.flat_map(paths, fn path ->
      parse_path(path, category, campaign)
    end)
  end

  defp parse_path(path, category, campaign) do
    schticks = path["schticks"] || []

    Enum.map(schticks, fn attributes ->
      parse_attributes(attributes, category, path, campaign)
    end)
  end

  defp parse_attributes(attributes, category, path, campaign) do
    category_name = titleize(category["name"])

    # Find or create the schtick
    schtick =
      case find_schtick(campaign.id, category_name, attributes["name"]) do
        nil -> %Schtick{campaign_id: campaign.id}
        existing -> existing
      end

    # Determine path name and color
    path_name = if path["name"], do: titleize(path["name"]), else: nil

    color =
      if path_name == "Core" do
        @colors["Core"]
      else
        @colors[category_name] || @colors["Core"]
      end

    # Find prerequisite
    prerequisite = find_prerequisite(attributes, category, path, campaign)

    # Build changeset
    attrs = %{
      campaign_id: campaign.id,
      category: category_name,
      name: attributes["name"],
      description: attributes["description"],
      bonus: attributes["bonus"] || false,
      archetypes: category["archetypes"],
      path: path_name,
      color: color,
      prerequisite_id: if(prerequisite, do: prerequisite.id, else: nil)
    }

    schtick
    |> Schtick.changeset(attrs)
    |> Repo.insert_or_update()
  rescue
    e ->
      require Logger
      Logger.warning("Failed to import schtick #{attributes["name"]}: #{inspect(e)}")
      {:error, e}
  end

  defp find_schtick(campaign_id, category, name) do
    from(s in Schtick,
      where: s.campaign_id == ^campaign_id and s.category == ^category and s.name == ^name
    )
    |> Repo.one()
  end

  defp find_prerequisite(attributes, category, _path, campaign) do
    category_name = titleize(category["name"])
    prereq_name = get_prerequisite_name(attributes)

    if prereq_name do
      find_schtick(campaign.id, category_name, prereq_name)
    else
      nil
    end
  end

  defp get_prerequisite_name(attributes) do
    cond do
      # Explicit prerequisite specified
      attributes["prerequisite"] ->
        attributes["prerequisite"]
        |> String.replace(".", "")

      # Check for roman numeral sequence (e.g., "Skill Name II" -> "Skill Name I")
      true ->
        name = attributes["name"] || ""
        parts = String.split(name, " ")
        last = List.last(parts) || ""

        previous = get_previous_numeral(last)

        if previous do
          parts
          |> List.replace_at(-1, previous)
          |> Enum.join(" ")
        else
          nil
        end
    end
  end

  defp get_previous_numeral(numeral) do
    upcase = String.upcase(numeral)

    if upcase in @roman_numerals do
      index = Enum.find_index(@roman_numerals, &(&1 == upcase))

      if index && index > 0 do
        Enum.at(@roman_numerals, index - 1)
      else
        nil
      end
    else
      nil
    end
  end

  defp titleize(nil), do: nil

  defp titleize(string) do
    string
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
