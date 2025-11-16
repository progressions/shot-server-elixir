defmodule ShotElixirWeb.Api.V2.CharacterController do
  require Logger
  use ShotElixirWeb, :controller

  alias ShotElixir.Characters
  alias ShotElixir.Characters.Character
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Get current campaign from user or params
    campaign_id = current_user.current_campaign_id || params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No current campaign set"})
    else
      characters = Characters.list_campaign_characters(campaign_id, params, current_user)

      Logger.debug(fn ->
        %{
          message: "Characters#index",
          params: params,
          campaign_id: campaign_id,
          returned: length(characters.characters)
        }
        |> Jason.encode!()
      end)

      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("index.json", characters: characters)
    end
  end

  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_access(character, current_user) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("show.json", character: character)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def create(conn, %{"character" => character_params}) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id || character_params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No current campaign set"})
    else
      params =
        character_params
        |> Map.put("campaign_id", campaign_id)
        |> Map.put("user_id", current_user.id)

      case Characters.create_character(params) do
        {:ok, character} ->
          # Broadcasting now happens automatically in Characters context
          conn
          |> put_status(:created)
          |> put_view(ShotElixirWeb.Api.V2.CharacterView)
          |> render("show.json", character: character)

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.CharacterView)
          |> render("error.json", changeset: changeset)
      end
    end
  end

  def update(conn, %{"id" => id, "character" => character_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_edit(character, current_user) do
      # Handle image upload if present
      # TODO: Implement image upload functionality
      # For now, just use the original character
      updated_character = character

      # Continue with normal update
      case Characters.update_character(updated_character, character_params) do
        {:ok, final_character} ->
          # Broadcasting now happens automatically in Characters context
          conn
          |> put_view(ShotElixirWeb.Api.V2.CharacterView)
          |> render("show.json", character: final_character)

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.CharacterView)
          |> render("error.json", changeset: changeset)
      end
    else
      nil ->
        {:error, :not_found}

      {:error, :forbidden} ->
        {:error, :forbidden}

      {:error, :unauthorized} ->
        {:error, :forbidden}
    end
  end

  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_edit(character, current_user),
         {:ok, _} <- Characters.delete_character(character) do
      # Broadcasting now happens automatically in Characters context
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Custom endpoints
  def duplicate(conn, %{"character_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_access(character, current_user),
         {:ok, new_character} <- Characters.duplicate_character(character, current_user) do
      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("show.json", character: new_character)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_edit(character, current_user) do
      # TODO: Implement Notion sync
      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("sync.json", character: character, status: "queued")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def pdf(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_access(character, current_user) do
      # TODO: Implement PDF generation
      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("pdf.json", character: character, url: nil)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def import(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id

    unless campaign_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No current campaign set"})
    else
      # TODO: Implement PDF import
      conn
      |> put_status(:not_implemented)
      |> json(%{error: "PDF import not yet implemented"})
    end
  end

  def autocomplete(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id || params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No current campaign set"})
    else
      characters = Characters.search_characters(campaign_id, params["q"] || "")

      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("autocomplete.json", characters: characters)
    end
  end

  # Authorization helpers
  defp authorize_character_access(character, user) do
    campaign_id = character.campaign_id
    campaigns = ShotElixir.Campaigns.get_user_campaigns(user.id)

    if Enum.any?(campaigns, fn c -> c.id == campaign_id end) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize_character_edit(character, user) do
    cond do
      character.user_id == user.id -> :ok
      user.gamemaster -> :ok
      true -> {:error, :forbidden}
    end
  end
end
