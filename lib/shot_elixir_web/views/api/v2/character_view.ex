defmodule ShotElixirWeb.Api.V2.CharacterView do

  def render("index.json", %{characters: characters}) do
    %{
      characters: Enum.map(characters, &render_character_lite/1),
      meta: %{
        total: length(characters),
        page: 1,
        per_page: 15
      }
    }
  end

  def render("show.json", %{character: character}) do
    %{character: render_character_full(character)}
  end

  def render("autocomplete.json", %{characters: characters}) do
    %{
      characters: Enum.map(characters, &render_character_autocomplete/1)
    }
  end

  def render("sync.json", %{character: character, status: status}) do
    %{
      character_id: character.id,
      status: status,
      message: "Character sync to Notion queued"
    }
  end

  def render("pdf.json", %{character: character, url: url}) do
    %{
      character_id: character.id,
      pdf_url: url,
      message: if(url, do: "PDF generated successfully", else: "PDF generation pending")
    }
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      errors: Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Enum.reduce(opts, msg, fn {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
        end)
      end)
    }
  end

  defp render_character_lite(character) do
    %{
      id: character.id,
      name: character.name,
      active: character.active,
      action_values: character.action_values,
      description: character.description,
      skills: character.skills,
      defense: character.defense,
      impairments: character.impairments,
      wealth: character.wealth,
      faction_id: character.faction_id,
      juncture_id: character.juncture_id,
      user_id: character.user_id,
      campaign_id: character.campaign_id,
      is_template: character.is_template,
      created_at: character.created_at,
      updated_at: character.updated_at
    }
  end

  defp render_character_full(character) do
    base = render_character_lite(character)

    # Add associations if they're loaded
    faction = case Map.get(character, :faction) do
      %Ecto.Association.NotLoaded{} -> nil
      faction -> render_faction_lite(faction)
    end

    juncture = case Map.get(character, :juncture) do
      %Ecto.Association.NotLoaded{} -> nil
      juncture -> render_juncture_lite(juncture)
    end

    schticks = case Map.get(character, :schticks) do
      %Ecto.Association.NotLoaded{} -> []
      schticks -> Enum.map(schticks, &render_schtick_lite/1)
    end

    weapons = case Map.get(character, :weapons) do
      %Ecto.Association.NotLoaded{} -> []
      weapons -> Enum.map(weapons, &render_weapon_lite/1)
    end

    Map.merge(base, %{
      faction: faction,
      juncture: juncture,
      schticks: schticks,
      weapons: weapons,
      image_url: character.image_url,
      summary: character.summary,
      status: character.status || []
    })
  end

  defp render_character_autocomplete(character) do
    %{
      id: character.id,
      name: character.name,
      archetype: get_in(character.action_values, ["Archetype"]),
      type: get_in(character.action_values, ["Type"])
    }
  end

  defp render_faction_lite(faction) do
    %{
      id: faction.id,
      name: faction.name
    }
  end

  defp render_juncture_lite(juncture) do
    %{
      id: juncture.id,
      name: juncture.name
    }
  end

  defp render_schtick_lite(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      category: schtick.category
    }
  end

  defp render_weapon_lite(weapon) do
    %{
      id: weapon.id,
      name: weapon.name,
      damage: weapon.damage
    }
  end
end