defmodule ShotElixirWeb.Api.V2.CharacterWeaponController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Characters
  alias ShotElixir.Weapons
  alias ShotElixir.Weapons.Carry
  alias ShotElixir.Guardian
  alias ShotElixir.Repo

  import Ecto.Query
  import ShotElixirWeb.CharacterAuthorization

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/characters/:character_id/weapons
  def index(conn, %{"character_id" => character_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         :ok <- authorize_character_access(character, current_user) do
      weapons = list_character_weapons(character_id)

      # Extract unique categories and junctures from the weapons
      categories =
        weapons
        |> Enum.map(& &1.category)
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
        |> Enum.sort()

      junctures =
        weapons
        |> Enum.map(& &1.juncture)
        |> Enum.reject(&is_nil/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()
        |> Enum.sort()

      conn
      |> put_view(ShotElixirWeb.Api.V2.WeaponView)
      |> render("index.json",
        weapons: weapons,
        meta: %{total: length(weapons)},
        categories: categories,
        junctures: junctures
      )
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # POST /api/v2/characters/:character_id/weapons
  def create(conn, %{"character_id" => character_id, "weapon" => weapon_params}) do
    current_user = Guardian.Plug.current_resource(conn)
    weapon_id = weapon_params["id"]

    with %{} = character <- Characters.get_character(character_id),
         :ok <- authorize_character_edit(character, current_user),
         %{} = _weapon <- Weapons.get_weapon(weapon_id),
         {:ok, _carry} <- create_carry(character_id, weapon_id) do
      # Return the updated character with weapon_ids
      updated_character = Characters.get_character(character_id)

      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("show.json", character: updated_character)
    else
      nil ->
        {:error, :not_found}

      {:error, :already_exists} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Character already has this weapon"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # DELETE /api/v2/characters/:character_id/weapons/:id
  def delete(conn, %{"character_id" => character_id, "id" => weapon_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         :ok <- authorize_character_edit(character, current_user),
         {:ok, _carry} <- delete_carry(character_id, weapon_id) do
      send_resp(conn, :no_content, "")
    else
      nil ->
        {:error, :not_found}

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Weapon not found on character"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp list_character_weapons(character_id) do
    query =
      from w in Weapons.Weapon,
        join: c in Carry,
        on: c.weapon_id == w.id,
        where: c.character_id == ^character_id,
        order_by: [asc: w.name]

    Repo.all(query)
  end

  defp create_carry(character_id, weapon_id) do
    # Check if carry already exists
    existing =
      Repo.get_by(Carry, character_id: character_id, weapon_id: weapon_id)

    if existing do
      {:error, :already_exists}
    else
      %Carry{}
      |> Ecto.Changeset.change(%{character_id: character_id, weapon_id: weapon_id})
      |> Repo.insert()
    end
  end

  defp delete_carry(character_id, weapon_id) do
    case Repo.get_by(Carry, character_id: character_id, weapon_id: weapon_id) do
      nil -> {:error, :not_found}
      carry -> Repo.delete(carry)
    end
  end
end
