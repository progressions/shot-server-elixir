defmodule ShotElixirWeb.Api.V2.WeaponController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Weapons
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/weapons
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      weapons = Weapons.list_weapons(current_user.current_campaign_id, params)
      render(conn, :index, weapons: weapons)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/weapons/:id
  def show(conn, %{"id" => id}) do
    weapon = Weapons.get_weapon(id)

    if weapon do
      render(conn, :show, weapon: weapon)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Weapon not found"})
    end
  end

  # POST /api/v2/weapons
  def create(conn, %{"weapon" => weapon_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Add campaign_id if not provided
    weapon_params = Map.put_new(weapon_params, "campaign_id", current_user.current_campaign_id)

    case Weapons.create_weapon(weapon_params) do
      {:ok, weapon} ->
        conn
        |> put_status(:created)
        |> render(:show, weapon: weapon)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # PATCH/PUT /api/v2/weapons/:id
  def update(conn, %{"id" => id, "weapon" => weapon_params}) do
    weapon = Weapons.get_weapon(id)

    cond do
      weapon == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Weapon not found"})

      true ->
        case Weapons.update_weapon(weapon, weapon_params) do
          {:ok, weapon} ->
            render(conn, :show, weapon: weapon)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:error, changeset: changeset)
        end
    end
  end

  # DELETE /api/v2/weapons/:id
  def delete(conn, %{"id" => id}) do
    weapon = Weapons.get_weapon(id)

    cond do
      weapon == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Weapon not found"})

      true ->
        case Weapons.delete_weapon(weapon) do
          {:ok, _weapon} ->
            send_resp(conn, :no_content, "")

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete weapon"})
        end
    end
  end
end
