defmodule ShotElixirWeb.Api.V2.WeaponView do
  def render("index.json", %{weapons: weapons, meta: meta}) do
    %{
      weapons: Enum.map(weapons, &render_weapon/1),
      meta: meta
    }
  end

  def render("show.json", %{weapon: weapon}) do
    render_weapon(weapon)
  end

  def render("error.json", %{changeset: changeset}) do
    %{
      success: false,
      errors: translate_errors(changeset)
    }
  end

  defp render_weapon(weapon) do
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
      image_url: get_image_url(weapon),
      active: weapon.active,
      campaign_id: weapon.campaign_id,
      entity_class: "Weapon",
      created_at: weapon.created_at,
      updated_at: weapon.updated_at
    }
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  # Rails-compatible image URL handling
  defp get_image_url(record) when is_map(record) do
    # Check if image_url is already in the record (pre-loaded)
    case Map.get(record, :image_url) do
      nil ->
        # Try to get entity type from struct, fallback to nil if plain map
        entity_type = case Map.get(record, :__struct__) do
          nil -> nil  # Plain map, skip ActiveStorage lookup
          struct_module -> struct_module |> Module.split() |> List.last()
        end

        if entity_type && Map.get(record, :id) do
          ShotElixir.ActiveStorage.get_image_url(entity_type, record.id)
        else
          nil
        end

      url ->
        url
    end
  end

  defp get_image_url(_), do: nil
end