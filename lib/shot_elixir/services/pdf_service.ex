defmodule ShotElixir.Services.PdfService do
  @moduledoc """
  PDF generation service that fills form fields in character_sheet.pdf using pdftk.
  Matches the Rails PdfService implementation exactly.
  """

  alias ShotElixir.Characters.Character
  alias ShotElixir.Repo

  @doc """
  Generates a filled PDF for the given character.
  Returns {:ok, temp_file_path} or {:error, reason}
  """
  def character_to_pdf(%Character{} = character) do
    character = character |> Repo.preload([:schticks, :weapons])
    fields = character_attributes_for_pdf(character)
    fill_fields(fields)
  end

  @doc """
  Fills PDF form fields using pdftk and returns path to filled PDF.
  """
  def fill_fields(field_map) when is_map(field_map) do
    template_path = Path.join(:code.priv_dir(:shot_elixir), "static/pdfs/character_sheet.pdf")

    unless File.exists?(template_path) do
      raise "PDF template not found at #{template_path}"
    end

    # Create temp file for filled PDF
    temp_file = Path.join(System.tmp_dir!(), "filled_#{:rand.uniform(1_000_000)}.pdf")

    # Create FDF data file
    fdf_path = create_fdf_file(field_map)

    # Call pdftk to fill the form
    case System.cmd("/usr/local/bin/pdftk", [
           template_path,
           "fill_form",
           fdf_path,
           "output",
           temp_file
         ]) do
      {_output, 0} ->
        # Clean up FDF file
        File.rm(fdf_path)
        {:ok, temp_file}

      {error, exit_code} ->
        File.rm(fdf_path)
        {:error, "pdftk failed with exit code #{exit_code}: #{error}"}
    end
  end

  @doc """
  Converts character data to PDF field format matching Rails implementation.
  """
  def character_attributes_for_pdf(%Character{} = character) do
    main_attack = character.action_values["MainAttack"]
    secondary_attack = character.action_values["SecondaryAttack"]

    schticks = character.schticks |> Enum.take(10)
    weapons = character.weapons |> Enum.take(4)

    # Format skills
    skills =
      character.skills
      |> Enum.filter(fn {_name, value} -> value > 0 end)
      |> Enum.map(fn {name, value} -> "#{name}: #{value}" end)
      |> Enum.join("\n")

    # Add backup attack to skills if present
    skills =
      if secondary_attack do
        backup_attack =
          "Backup Attack: #{secondary_attack} (#{character.action_values[secondary_attack]})"

        "#{backup_attack}\n#{skills}"
      else
        skills
      end

    # Build the field map
    %{
      "Name" => character.name,
      "Attack Type" => main_attack,
      "Attack" => get_in(character.action_values, [main_attack]),
      "Defense" => character.action_values["Defense"],
      "Toughness" => character.action_values["Toughness"],
      "Fortune Type" => character.action_values["Fortune Type"],
      "Fortune" => character.action_values["Max Fortune"],
      "Speed" => character.action_values["Speed"],
      # Schticks
      "Schtick 1 Title" => get_field(schticks, 0, :name),
      "Schtick 1 Text" => "\n" <> (get_field(schticks, 0, :description) || ""),
      "Schtick 2 Title" => get_field(schticks, 1, :name),
      "Schtick 2 Text" => "\n" <> (get_field(schticks, 1, :description) || ""),
      "Schtick 3 Title" => get_field(schticks, 2, :name),
      "Schtick 3 Text" => "\n" <> (get_field(schticks, 2, :description) || ""),
      "Schtick 4 Title" => get_field(schticks, 3, :name),
      "Schtick 4 Text" => "\n" <> (get_field(schticks, 3, :description) || ""),
      "Schtick 5 Title" => get_field(schticks, 4, :name),
      "Schtick 5 Text" => "\n" <> (get_field(schticks, 4, :description) || ""),
      "Schtick 6 Title" => get_field(schticks, 5, :name),
      "Schtick 6 Text" => "\n" <> (get_field(schticks, 5, :description) || ""),
      "Schtick 7 Title" => get_field(schticks, 6, :name),
      "Schtick 7 Text" => "\n" <> (get_field(schticks, 6, :description) || ""),
      "Schtick 8 Title" => get_field(schticks, 7, :name),
      "Schtick 8 Text" => "\n" <> (get_field(schticks, 7, :description) || ""),
      "Schtick 9 Title" => get_field(schticks, 8, :name),
      "Schtick 9 Text" => "\n" <> (get_field(schticks, 8, :description) || ""),
      "Schtick 10 Title" => get_field(schticks, 9, :name),
      "Schtick 10 Text" => "\n" <> (get_field(schticks, 9, :description) || ""),
      # Weapons (always include Unarmed as weapon 1)
      "Weapon 1 Name" => "Unarmed",
      "Weapon 1 Damage" => 7,
      "Weapon 1 Concealment" => "",
      "Weapon 1 Reload" => "",
      "Weapon 2 Name" => get_field(weapons, 0, :name),
      "Weapon 2 Damage" => get_field(weapons, 0, :damage),
      "Weapon 2 Concealment" => get_field(weapons, 0, :concealment),
      "Weapon 2 Reload" => get_field(weapons, 0, :reload_value),
      "Weapon 3 Name" => get_field(weapons, 1, :name),
      "Weapon 3 Damage" => get_field(weapons, 1, :damage),
      "Weapon 3 Concealment" => get_field(weapons, 1, :concealment),
      "Weapon 3 Reload" => get_field(weapons, 1, :reload_value),
      "Weapon 4 Name" => get_field(weapons, 2, :name),
      "Weapon 4 Damage" => get_field(weapons, 2, :damage),
      "Weapon 4 Concealment" => get_field(weapons, 2, :concealment),
      "Weapon 4 Reload" => get_field(weapons, 2, :reload_value),
      "Weapon 5 Name" => get_field(weapons, 3, :name),
      "Weapon 5 Damage" => get_field(weapons, 3, :damage),
      "Weapon 5 Concealment" => get_field(weapons, 3, :concealment),
      "Weapon 5 Reload" => get_field(weapons, 3, :reload_value),
      # Other fields
      "Gear" => "",
      "Skills" => "\n#{skills}",
      "Archetype" => character.action_values["Archetype"],
      "Quote" => "",
      "Juncture" => "",
      "Wealth" => "",
      "Story" => strip_html(character.description["Background"]),
      "Melodramatic Hook" => strip_html(character.description["Melodramatic Hook"]),
      "Important GMCs" => "",
      "Credits" => ""
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Create FDF file for pdftk form filling
  defp create_fdf_file(field_map) do
    fdf_path = Path.join(System.tmp_dir!(), "fields_#{:rand.uniform(1_000_000)}.fdf")

    fdf_content = """
    %FDF-1.2
    1 0 obj
    <<
    /FDF << /Fields [
    #{format_fdf_fields(field_map)}
    ] >>
    >>
    endobj
    trailer
    <<
    /Root 1 0 R
    >>
    %%EOF
    """

    File.write!(fdf_path, fdf_content)
    fdf_path
  end

  # Format fields for FDF file
  defp format_fdf_fields(field_map) do
    field_map
    |> Enum.map(fn {key, value} ->
      escaped_value = escape_fdf_value(to_string(value))
      "<< /T (#{key}) /V (#{escaped_value}) >>"
    end)
    |> Enum.join("\n")
  end

  # Escape special characters for FDF format
  defp escape_fdf_value(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("(", "\\(")
    |> String.replace(")", "\\)")
    |> String.replace("\n", "\\r")
  end

  # Safely get field from list element
  defp get_field(list, index, field) do
    case Enum.at(list, index) do
      nil ->
        nil

      item ->
        value = Map.get(item, field)
        if is_binary(value), do: strip_html(value), else: value
    end
  end

  # Strip HTML tags (matching Rails FightPoster.strip_html_p_to_br)
  defp strip_html(nil), do: nil

  defp strip_html(text) do
    text
    |> String.replace(~r/<p>/, "")
    |> String.replace(~r/<\/p>/, "\n")
    |> String.replace(~r/<br\s*\/?>/, "\n")
    |> String.replace(~r/<[^>]*>/, "")
    |> String.trim()
  end
end
