defmodule ShotElixirWeb.Api.V2.WeaponController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Weapons
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/weapons
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      result = Weapons.list_weapons(current_user.current_campaign_id, params)

      conn
      |> put_view(ShotElixirWeb.Api.V2.WeaponView)
      |> render("index.json", weapons: result.weapons, meta: result.meta)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # POST /api/v2/weapons/batch
  def batch(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, campaign_id} <- ensure_campaign(current_user),
         ids when is_list(ids) <- parse_ids(params["ids"]),
         {:ok, weapons} <- fetch_batch(campaign_id, ids) do
      serialized = Enum.map(weapons, &serialize_batch_weapon/1)
      json(conn, %{weapons: serialized})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      {:error, :invalid_request} ->
        json(conn, %{weapons: []})
    end
  end

  # GET /api/v2/weapons/categories
  def categories(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, campaign_id} <- ensure_campaign(current_user) do
      categories = Weapons.list_categories(campaign_id, params["search"])
      json(conn, %{categories: categories})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/weapons/junctures
  def junctures(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, campaign_id} <- ensure_campaign(current_user) do
      junctures = Weapons.list_junctures(campaign_id, params["search"])
      json(conn, %{junctures: junctures})
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/weapons/:id
  def show(conn, %{"id" => id}) do
    weapon = Weapons.get_weapon(id)

    if weapon do
      conn
      |> put_view(ShotElixirWeb.Api.V2.WeaponView)
      |> render("show.json", weapon: weapon)
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
        |> put_view(ShotElixirWeb.Api.V2.WeaponView)
        |> render("show.json", weapon: weapon)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.WeaponView)
        |> render("error.json", changeset: changeset)
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
        # Handle image upload if present
        case conn.params["image"] do
          %Plug.Upload{} = upload ->
            # Upload image to ImageKit
            case ShotElixir.Services.ImagekitService.upload_plug(upload) do
              {:ok, upload_result} ->
                # Attach image to weapon via ActiveStorage
                case ShotElixir.ActiveStorage.attach_image("Weapon", weapon.id, upload_result) do
                  {:ok, _attachment} ->
                    # Reload weapon to get fresh data after image attachment
                    weapon = Weapons.get_weapon(weapon.id)
                    # Continue with weapon update
                    case Weapons.update_weapon(weapon, weapon_params) do
                      {:ok, weapon} ->
                        conn
                        |> put_view(ShotElixirWeb.Api.V2.WeaponView)
                        |> render("show.json", weapon: weapon)

                      {:error, changeset} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> put_view(ShotElixirWeb.Api.V2.WeaponView)
                        |> render("error.json", changeset: changeset)
                    end

                  {:error, changeset} ->
                    conn
                    |> put_status(:unprocessable_entity)
                    |> put_view(ShotElixirWeb.Api.V2.WeaponView)
                    |> render("error.json", changeset: changeset)
                end

              {:error, reason} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Failed to upload image: #{inspect(reason)}"})
            end

          _ ->
            # No image upload, just update weapon
            case Weapons.update_weapon(weapon, weapon_params) do
              {:ok, weapon} ->
                conn
                |> put_view(ShotElixirWeb.Api.V2.WeaponView)
                |> render("show.json", weapon: weapon)

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> put_view(ShotElixirWeb.Api.V2.WeaponView)
                |> render("error.json", changeset: changeset)
            end
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

  # DELETE /api/v2/weapons/:id/image
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, campaign_id} <- ensure_campaign(current_user),
         %{} = weapon <- Weapons.get_weapon(id),
         true <- weapon.campaign_id == campaign_id,
         :ok <- require_gamemaster(current_user),
         {:ok, weapon} <- Weapons.remove_image(weapon) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.WeaponView)
      |> render("show.json", weapon: weapon)
    else
      {:error, :unauthorized} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Not authenticated"})

      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      false ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Weapon not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemasters can perform this action"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Weapon not found"})
    end
  end

  defp ensure_campaign(nil), do: {:error, :unauthorized}
  defp ensure_campaign(%{current_campaign_id: nil}), do: {:error, :no_campaign}
  defp ensure_campaign(%{current_campaign_id: campaign_id}), do: {:ok, campaign_id}

  defp parse_ids(nil), do: []

  defp parse_ids("") do
    []
  end

  defp parse_ids(ids) when is_list(ids), do: ids

  defp parse_ids(ids) when is_binary(ids) do
    ids
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_ids(_), do: []

  defp fetch_batch(_campaign_id, []), do: {:error, :invalid_request}

  defp fetch_batch(campaign_id, ids) do
    weapons = Weapons.get_weapons_batch(campaign_id, ids)
    {:ok, weapons}
  end

  defp serialize_batch_weapon(weapon) do
    %{
      id: weapon.id,
      name: weapon.name,
      description: weapon.description,
      image_url: weapon.image_url,
      damage: weapon.damage,
      concealment: weapon.concealment,
      reload_value: weapon.reload_value,
      mook_bonus: weapon.mook_bonus,
      kachunk: weapon.kachunk,
      entity_class: "Weapon"
    }
  end

  defp require_gamemaster(user) do
    if user.admin || user.gamemaster do
      :ok
    else
      {:error, :forbidden}
    end
  end
end
