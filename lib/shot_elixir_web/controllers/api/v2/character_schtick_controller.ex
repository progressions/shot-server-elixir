defmodule ShotElixirWeb.Api.V2.CharacterSchtickController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Characters
  alias ShotElixir.Schticks
  alias ShotElixir.Schticks.CharacterSchtick
  alias ShotElixir.Guardian
  alias ShotElixir.Repo

  import Ecto.Query
  import ShotElixirWeb.CharacterAuthorization

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/characters/:character_id/schticks
  def index(conn, %{"character_id" => character_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         :ok <- authorize_character_access(character, current_user) do
      schticks = list_character_schticks(character_id)

      conn
      |> put_view(ShotElixirWeb.Api.V2.SchticksView)
      |> render("index.json", schticks: schticks, meta: %{total: length(schticks)})
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # POST /api/v2/characters/:character_id/schticks
  def create(conn, %{"character_id" => character_id, "schtick" => schtick_params}) do
    current_user = Guardian.Plug.current_resource(conn)
    schtick_id = schtick_params["id"]

    with %{} = character <- Characters.get_character(character_id),
         :ok <- authorize_character_edit(character, current_user),
         %{} = _schtick <- Schticks.get_schtick(schtick_id),
         {:ok, _character_schtick} <- create_character_schtick(character_id, schtick_id) do
      # Return the updated character with schtick_ids
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
        |> json(%{error: "Character already has this schtick"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # DELETE /api/v2/characters/:character_id/schticks/:id
  def delete(conn, %{"character_id" => character_id, "id" => schtick_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = character <- Characters.get_character(character_id),
         :ok <- authorize_character_edit(character, current_user),
         {:ok, _character_schtick} <- delete_character_schtick(character_id, schtick_id) do
      send_resp(conn, :no_content, "")
    else
      nil ->
        {:error, :not_found}

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Schtick not found on character"})

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp list_character_schticks(character_id) do
    query =
      from s in Schticks.Schtick,
        join: cs in CharacterSchtick,
        on: cs.schtick_id == s.id,
        where: cs.character_id == ^character_id,
        order_by: [asc: s.name]

    Repo.all(query)
  end

  defp create_character_schtick(character_id, schtick_id) do
    # Check if character_schtick already exists
    existing =
      Repo.get_by(CharacterSchtick, character_id: character_id, schtick_id: schtick_id)

    if existing do
      {:error, :already_exists}
    else
      %CharacterSchtick{}
      |> Ecto.Changeset.change(%{character_id: character_id, schtick_id: schtick_id})
      |> Repo.insert()
    end
  end

  defp delete_character_schtick(character_id, schtick_id) do
    case Repo.get_by(CharacterSchtick, character_id: character_id, schtick_id: schtick_id) do
      nil -> {:error, :not_found}
      character_schtick -> Repo.delete(character_schtick)
    end
  end
end
