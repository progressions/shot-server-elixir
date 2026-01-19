defmodule ShotElixirWeb.Api.V2.ImagePositionController do
  use ShotElixirWeb, :controller

  alias ShotElixir.ImagePositions
  alias ShotElixir.ImagePositions.ImagePosition
  alias ShotElixir.Guardian
  alias ShotElixir.Repo

  action_fallback ShotElixirWeb.FallbackController

  def show(conn, %{"positionable_type" => type, "positionable_id" => id}) do
    with {:ok, _positionable} <- authorize_positionable(conn, type, id) do
      positions =
        ImagePositions.list_for(type, id)
        |> Enum.map(&serialize/1)

      json(conn, positions)
    else
      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{error: message})
    end
  end

  def create(conn, params) do
    with {:ok, type, id, attrs} <- normalize_params(params),
         {:ok, _positionable} <- authorize_positionable(conn, type, id),
         {:ok, %ImagePosition{} = position} <- ImagePositions.create(attrs) do
      json(conn, serialize(position))
    else
      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{error: message})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Validation failed",
          details: translate_changeset_errors(changeset)
        })
    end
  end

  def update(conn, params) do
    with {:ok, type, id, attrs} <- normalize_params(params),
         {:ok, _positionable} <- authorize_positionable(conn, type, id),
         {:ok, %ImagePosition{} = position} <- ImagePositions.upsert(type, id, attrs) do
      json(conn, serialize(position))
    else
      {:error, status, message} ->
        conn
        |> put_status(status)
        |> json(%{error: message})

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{
          error: "Validation failed",
          details: translate_changeset_errors(changeset)
        })
    end
  end

  defp normalize_params(%{"image_position" => attrs} = params) do
    attrs = Map.new(attrs)

    type = attrs["positionable_type"] || attrs[:positionable_type] || params["positionable_type"]
    id = attrs["positionable_id"] || attrs[:positionable_id] || params["positionable_id"]

    cond do
      is_nil(type) or is_nil(id) ->
        {:error, :bad_request, "positionable_type and positionable_id are required"}

      true ->
        attrs =
          attrs
          |> Map.put("positionable_type", type)
          |> Map.put("positionable_id", id)

        {:ok, type, id, attrs}
    end
  end

  defp normalize_params(%{"positionable_type" => type, "positionable_id" => id} = params) do
    attrs =
      params
      |> Map.get("image_position", %{})
      |> Map.new()
      |> Map.put("positionable_type", type)
      |> Map.put("positionable_id", id)

    {:ok, type, id, attrs}
  end

  defp normalize_params(_), do: {:error, :bad_request, "image_position parameters are required"}

  defp authorize_positionable(conn, type, id) do
    with {:ok, user} <- current_user(conn),
         {:ok, module} <- resolve_positionable(type),
         {:ok, record} <- fetch_positionable(module, id),
         true <- authorized?(user, record) do
      {:ok, record}
    else
      false -> {:error, :forbidden, "Access denied"}
      {:error, :unsupported_type} -> {:error, :bad_request, "Unsupported positionable_type"}
      {:error, :not_found} -> {:error, :not_found, "Positionable not found"}
      {:error, :unauthenticated} -> {:error, :unauthorized, "Not authenticated"}
    end
  end

  defp current_user(conn) do
    case Guardian.Plug.current_resource(conn) do
      nil -> {:error, :unauthenticated}
      user -> {:ok, user}
    end
  end

  @positionable_modules %{
    "Adventure" => ShotElixir.Adventures.Adventure,
    "Campaign" => ShotElixir.Campaigns.Campaign,
    "Character" => ShotElixir.Characters.Character,
    "Faction" => ShotElixir.Factions.Faction,
    "Fight" => ShotElixir.Fights.Fight,
    "Juncture" => ShotElixir.Junctures.Juncture,
    "Party" => ShotElixir.Parties.Party,
    "Site" => ShotElixir.Sites.Site,
    "User" => ShotElixir.Accounts.User,
    "Vehicle" => ShotElixir.Vehicles.Vehicle
  }

  defp resolve_positionable(type) do
    case Map.fetch(@positionable_modules, type) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unsupported_type}
    end
  end

  defp fetch_positionable(module, id) do
    case Repo.get(module, id) do
      nil -> {:error, :not_found}
      record -> {:ok, record}
    end
  end

  defp authorized?(user, record) do
    cond do
      user.admin ->
        true

      Map.has_key?(record, :campaign_id) and not is_nil(record.campaign_id) ->
        user.current_campaign_id == record.campaign_id or user.id == record.user_id

      match?(%ShotElixir.Campaigns.Campaign{}, record) ->
        user.current_campaign_id == record.id

      match?(%ShotElixir.Accounts.User{}, record) ->
        user.id == record.id

      true ->
        false
    end
  end

  defp serialize(%ImagePosition{} = position) do
    %{
      id: position.id,
      positionable_type: position.positionable_type,
      positionable_id: position.positionable_id,
      context: position.context,
      x_position: position.x_position,
      y_position: position.y_position,
      style_overrides: position.style_overrides,
      created_at: position.created_at,
      updated_at: position.updated_at
    }
  end

  # Helper to translate Ecto.Changeset errors to JSON format
  defp translate_changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
