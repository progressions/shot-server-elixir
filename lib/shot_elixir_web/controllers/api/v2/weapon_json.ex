defmodule ShotElixirWeb.Api.V2.WeaponJSON do
  # alias ShotElixir.Weapons.Weapon

  def index(%{weapons: weapons, categories: categories, junctures: junctures, meta: meta}) do
    %{
      weapons: Enum.map(weapons, &weapon_json/1),
      categories: categories,
      junctures: junctures,
      meta: meta
    }
  end

  def show(%{weapon: weapon}) do
    %{weapon: weapon_json(weapon)}
  end

  def error(%{changeset: changeset}) do
    %{
      errors:
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Enum.reduce(opts, msg, fn {key, value}, acc ->
            String.replace(acc, "%{#{key}}", to_string(value))
          end)
        end)
    }
  end

  defp weapon_json(weapon) do
    %{
      id: weapon.id,
      name: weapon.name,
      description: weapon.description,
      damage: weapon.damage,
      concealment: weapon.concealment,
      reload_value: weapon.reload_value,
      juncture: weapon.juncture,
      mook_bonus: weapon.mook_bonus,
      category: weapon.category,
      kachunk: weapon.kachunk,
      image_url: weapon.image_url,
      active: weapon.active,
      campaign_id: weapon.campaign_id,
      created_at: weapon.created_at,
      updated_at: weapon.updated_at,
      entity_class: "Weapon"
    }
  end
end
