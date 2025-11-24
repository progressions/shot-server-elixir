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
      {:error, "PDF template not found at #{template_path}"}
    else
      with {:ok, fdf_path} <- create_fdf_file(field_map),
           {:ok, temp_file} <- run_pdftk(template_path, fdf_path) do
        File.rm(fdf_path)
        {:ok, temp_file}
      else
        {:error, _reason} = error ->
          # Cleanup is handled within helper functions
          error
      end
    end
  end

  # Run pdftk command with error handling
  defp run_pdftk(template_path, fdf_path) do
    # Determine pdftk path: try System.find_executable, then config, then fallback
    pdftk_path =
      System.find_executable("pdftk") ||
        Application.get_env(:shot_elixir, :pdftk_path, "/usr/local/bin/pdftk")

    temp_file =
      Path.join(System.tmp_dir!(), "filled_#{System.unique_integer([:positive, :monotonic])}.pdf")

    case System.cmd(pdftk_path, [
           template_path,
           "fill_form",
           fdf_path,
           "output",
           temp_file
         ]) do
      {_output, 0} ->
        {:ok, temp_file}

      {error, exit_code} ->
        {:error, "pdftk failed with exit code #{exit_code}: #{error}"}
    end
  rescue
    e in ErlangError ->
      {:error, "pdftk command failed: #{inspect(e)}"}
  end

  @doc """
  Converts character data to PDF field format matching Rails implementation.
  """
  def character_attributes_for_pdf(%Character{} = character) do
    main_attack = get_in(character.action_values, ["MainAttack"]) || "Unarmed"
    secondary_attack = get_in(character.action_values, ["SecondaryAttack"])

    schticks = character.schticks |> Enum.take(10)
    weapons = character.weapons |> Enum.take(4)

    # Format skills
    skills =
      (character.skills || %{})
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
      "Schtick 1 Text" => prepend_newline(get_field(schticks, 0, :description)),
      "Schtick 2 Title" => get_field(schticks, 1, :name),
      "Schtick 2 Text" => prepend_newline(get_field(schticks, 1, :description)),
      "Schtick 3 Title" => get_field(schticks, 2, :name),
      "Schtick 3 Text" => prepend_newline(get_field(schticks, 2, :description)),
      "Schtick 4 Title" => get_field(schticks, 3, :name),
      "Schtick 4 Text" => prepend_newline(get_field(schticks, 3, :description)),
      "Schtick 5 Title" => get_field(schticks, 4, :name),
      "Schtick 5 Text" => prepend_newline(get_field(schticks, 4, :description)),
      "Schtick 6 Title" => get_field(schticks, 5, :name),
      "Schtick 6 Text" => prepend_newline(get_field(schticks, 5, :description)),
      "Schtick 7 Title" => get_field(schticks, 6, :name),
      "Schtick 7 Text" => prepend_newline(get_field(schticks, 6, :description)),
      "Schtick 8 Title" => get_field(schticks, 7, :name),
      "Schtick 8 Text" => prepend_newline(get_field(schticks, 7, :description)),
      "Schtick 9 Title" => get_field(schticks, 8, :name),
      "Schtick 9 Text" => prepend_newline(get_field(schticks, 8, :description)),
      "Schtick 10 Title" => get_field(schticks, 9, :name),
      "Schtick 10 Text" => prepend_newline(get_field(schticks, 9, :description)),
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
      "Story" => strip_html(get_in(character.description, ["Background"])),
      "Melodramatic Hook" => strip_html(get_in(character.description, ["Melodramatic Hook"])),
      "Important GMCs" => "",
      "Credits" => ""
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  # Create FDF file for pdftk form filling
  defp create_fdf_file(field_map) do
    fdf_path =
      Path.join(
        System.tmp_dir!(),
        "fields_#{System.unique_integer([:positive, :monotonic])}.fdf"
      )

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

    case File.write(fdf_path, fdf_content) do
      :ok -> {:ok, fdf_path}
      {:error, reason} -> {:error, "Failed to create FDF file: #{inspect(reason)}"}
    end
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

  # Prepend newline to text for PDF formatting
  defp prepend_newline(nil), do: nil
  defp prepend_newline(text), do: "\n" <> text

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

  @doc """
  Creates a character from an uploaded PDF file.
  Returns {:ok, character_attrs, weapons, schticks} or {:error, reason}
  The character attrs can be used to create a new character, and weapons/schticks
  should be associated after the character is saved.
  """
  def pdf_to_character(%Plug.Upload{} = upload, campaign, user) do
    # Save uploaded file temporarily
    temp_file_path =
      Path.join(
        System.tmp_dir!(),
        "uploaded_#{System.unique_integer([:positive, :monotonic])}.pdf"
      )

    case File.cp(upload.path, temp_file_path) do
      :ok ->
        result = extract_character_from_pdf(temp_file_path, campaign, user)
        File.rm(temp_file_path)
        result

      {:error, reason} ->
        {:error, "Failed to save uploaded PDF: #{inspect(reason)}"}
    end
  end

  # Extract character data from PDF using pdftk
  defp extract_character_from_pdf(pdf_path, campaign, user) do
    case get_pdf_fields(pdf_path) do
      {:ok, fields} ->
        if has_required_fields?(fields) do
          build_character_from_fields(fields, campaign, user)
        else
          {:error, "Invalid PDF: Missing required fields"}
        end

      {:error, _reason} = error ->
        error
    end
  end

  # Get form fields from PDF using pdftk
  defp get_pdf_fields(pdf_path) do
    pdftk_path =
      System.find_executable("pdftk") ||
        Application.get_env(:shot_elixir, :pdftk_path, "/usr/local/bin/pdftk")

    case System.cmd(pdftk_path, [pdf_path, "dump_data_fields"]) do
      {output, 0} ->
        fields = parse_pdftk_fields(output)
        {:ok, fields}

      {error, exit_code} ->
        {:error, "pdftk failed with exit code #{exit_code}: #{error}"}
    end
  rescue
    e in ErlangError ->
      {:error, "pdftk command failed: #{inspect(e)}"}
  end

  # Parse pdftk dump_data_fields output into a map
  defp parse_pdftk_fields(output) do
    output
    |> String.split("---")
    |> Enum.reduce(%{}, fn field_block, acc ->
      lines = String.split(field_block, "\n", trim: true)
      field_name = extract_field_value(lines, "FieldName:")
      field_value = extract_field_value(lines, "FieldValue:")

      if field_name do
        Map.put(acc, field_name, field_value || "")
      else
        acc
      end
    end)
  end

  defp extract_field_value(lines, prefix) do
    lines
    |> Enum.find(&String.starts_with?(&1, prefix))
    |> case do
      nil -> nil
      line -> String.trim_leading(line, prefix) |> String.trim()
    end
  end

  # Check if PDF has required fields
  defp has_required_fields?(fields) do
    Map.has_key?(fields, "Name")
  end

  # Build character from PDF fields
  defp build_character_from_fields(fields, campaign, user) do
    base_name =
      get_pdf_field_value(fields, "Name") || get_pdf_field_value(fields, "Archetype") ||
        "Unnamed Character"

    # Generate unique name if the base name already exists
    unique_name = ShotElixir.Characters.generate_unique_name(base_name, campaign.id)

    character_attrs = %{
      name: unique_name,
      campaign_id: campaign.id,
      user_id: user.id,
      action_values: action_values_from_pdf_fields(fields),
      wealth: get_pdf_field_value(fields, "Wealth"),
      skills: get_skills_from_pdf_fields(fields),
      description: get_description_from_pdf_fields(fields),
      active: true,
      impairments: 0
    }

    # Get associated data
    weapons = get_weapons_from_pdf_fields(fields, campaign)
    schticks = get_schticks_from_pdf_fields(fields, campaign)

    # Find juncture if specified
    character_attrs =
      case get_pdf_field_value(fields, "Juncture") do
        nil ->
          character_attrs

        "" ->
          character_attrs

        juncture_name ->
          case ShotElixir.Junctures.get_juncture_by_name(campaign.id, juncture_name) do
            nil -> character_attrs
            juncture -> Map.put(character_attrs, :juncture_id, juncture.id)
          end
      end

    {:ok, character_attrs, weapons, schticks}
  end

  defp get_pdf_field_value(fields, field_name) do
    case Map.get(fields, field_name) do
      "" -> nil
      value -> value
    end
  end

  defp action_values_from_pdf_fields(fields) do
    main_attack = get_pdf_field_value(fields, "Attack Type") || "Unarmed"

    base_values = %{
      "MainAttack" => main_attack,
      main_attack => get_pdf_field_value(fields, "Attack"),
      "Defense" => get_pdf_field_value(fields, "Defense"),
      "Toughness" => get_pdf_field_value(fields, "Toughness"),
      "FortuneType" => get_pdf_field_value(fields, "Fortune Type"),
      "Max Fortune" => get_pdf_field_value(fields, "Fortune"),
      "Fortune" => get_pdf_field_value(fields, "Fortune"),
      "Speed" => get_pdf_field_value(fields, "Speed"),
      "SecondaryAttack" => nil,
      "Type" => "PC",
      "Archetype" => get_pdf_field_value(fields, "Archetype")
    }

    # Merge secondary attack if present
    case get_secondary_attack_from_pdf_fields(fields) do
      nil -> base_values
      secondary -> Map.merge(base_values, secondary)
    end
  end

  defp get_secondary_attack_from_pdf_fields(fields) do
    skills_text = get_pdf_field_value(fields, "Skills") || ""

    skills_text
    |> String.split(~r/\r\n?/)
    |> Enum.find_value(fn line ->
      if String.contains?(line, "Backup Attack") do
        # Try colon format: "Backup Attack: [Type]: [Value]"
        case Regex.run(~r/\s*Backup Attack\s*:\s*(.+?)\s*:\s*(\d+)\s*$/, line) do
          [_, skill_name, skill_value] ->
            %{
              "SecondaryAttack" => String.trim(skill_name),
              String.trim(skill_name) => String.to_integer(skill_value)
            }

          nil ->
            # Try space format: "Backup Attack: [Type] [Value]"
            case Regex.run(~r/\s*Backup Attack\s*:\s*(.+?)\s+(\d+)\s*$/, line) do
              [_, skill_name, skill_value] ->
                %{
                  "SecondaryAttack" => String.trim(skill_name),
                  String.trim(skill_name) => String.to_integer(skill_value)
                }

              nil ->
                nil
            end
        end
      end
    end)
  end

  defp get_skills_from_pdf_fields(fields) do
    skills_text = get_pdf_field_value(fields, "Skills") || ""

    skills_text
    |> String.split(~r/\r\n?/)
    |> Enum.reject(&String.contains?(&1, "Backup Attack"))
    |> Enum.reduce(%{}, fn line, acc ->
      # Match both formats: "Skill Name: Value" and "Skill Name Value"
      case Regex.run(~r/^\s*(.+?)\s*:\s*(\d+)\s*$/, line) ||
             Regex.run(~r/^\s*(.+?)\s+(\d+)\s*$/, line) do
        [_, skill_name, skill_value] ->
          Map.put(acc, String.trim(skill_name), String.to_integer(skill_value))

        nil ->
          acc
      end
    end)
  end

  defp get_description_from_pdf_fields(fields) do
    %{
      "Melodramatic Hook" => get_pdf_field_value(fields, "Melodramatic Hook") || "",
      "Background" => get_pdf_field_value(fields, "Story") || ""
    }
  end

  defp get_weapons_from_pdf_fields(fields, campaign) do
    1..5
    |> Enum.map(&get_weapon_from_pdf(fields, &1, campaign))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp get_weapon_from_pdf(fields, index, campaign) do
    name = get_pdf_field_value(fields, "Weapon #{index} Name")

    if name && name != "" && name != "Unarmed" do
      damage = parse_integer(get_pdf_field_value(fields, "Weapon #{index} Damage"))
      concealment = get_pdf_field_value(fields, "Weapon #{index} Concealment") || ""
      reload_value = get_pdf_field_value(fields, "Weapon #{index} Reload") || ""

      # Find or create weapon
      case ShotElixir.Weapons.get_weapon_by_name(campaign.id, name) do
        nil ->
          {:ok, weapon} =
            ShotElixir.Weapons.create_weapon(%{
              name: name,
              campaign_id: campaign.id,
              damage: damage,
              concealment: concealment,
              reload_value: reload_value,
              description: "",
              kachunk: "",
              juncture: ""
            })

          weapon

        weapon ->
          weapon
      end
    end
  end

  defp get_schticks_from_pdf_fields(fields, campaign) do
    1..10
    |> Enum.map(&get_schtick_from_pdf(fields, &1, campaign))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
  end

  defp get_schtick_from_pdf(fields, index, campaign) do
    name = get_pdf_field_value(fields, "Schtick #{index} Title")

    if name && name != "" do
      # Only find existing schticks, don't create new ones
      ShotElixir.Schticks.get_schtick_by_name(campaign.id, name)
    end
  end

  defp parse_integer(nil), do: nil
  defp parse_integer(""), do: nil
  defp parse_integer(value) when is_integer(value), do: value

  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> nil
    end
  end
end
