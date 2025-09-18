defmodule ShotElixirWeb.Api.V2.UserController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian
  alias ShotElixirWeb.ErrorJSON

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/users
  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.admin do
      users = Accounts.list_users()
      render(conn, :index, users: users)
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden"})
    end
  end

  # GET /api/v2/users/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    # First check if the user exists
    case Accounts.get_user(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Not found"})

      user ->
        # Then check authorization
        if current_user.admin || current_user.id == id do
          render(conn, :show, user: user)
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Forbidden"})
        end
    end
  end

  # GET /api/v2/users/current
  def current(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    if user do
      # Preload associations if needed
      user = user |> ShotElixir.Repo.preload([:current_campaign, :campaigns, :player_campaigns])
      render(conn, :current, user: user)
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Not authenticated"})
    end
  end

  # GET /api/v2/users/profile or /api/v2/users/:id/profile
  def profile(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user do
      case params do
        %{"id" => id} ->
          # Accessing a specific user's profile
          if current_user.admin || current_user.id == id do
            case Accounts.get_user(id) do
              nil ->
                conn
                |> put_status(:not_found)
                |> json(%{error: "Not found"})
              user ->
                user = user |> ShotElixir.Repo.preload([:current_campaign, :campaigns, :player_campaigns])
                render(conn, :profile, user: user)
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Forbidden"})
          end
        _ ->
          # Accessing own profile - always allowed
          user = current_user |> ShotElixir.Repo.preload([:current_campaign, :campaigns, :player_campaigns])
          render(conn, :profile, user: user)
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Not authenticated"})
    end
  end

  # PATCH /api/v2/users/profile
  def update_profile(conn, %{"user" => user_params}) do
    user = Guardian.Plug.current_resource(conn)

    case Accounts.update_user(user, user_params) do
      {:ok, updated_user} ->
        render(conn, :show, user: updated_user)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # POST /api/v2/users
  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        {:ok, token, _claims} = Guardian.encode_and_sign(user)

        conn
        |> put_status(:created)
        |> put_resp_header("authorization", "Bearer #{token}")
        |> render(:show, user: user, token: token)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # PATCH/PUT /api/v2/users/:id
  def update(conn, %{"id" => id, "user" => user_params}) do
    user = Accounts.get_user!(id)
    current_user = Guardian.Plug.current_resource(conn)

    # Check authorization - only admin or self can update
    if current_user.admin || current_user.id == user.id do
      case Accounts.update_user(user, user_params) do
        {:ok, updated_user} ->
          render(conn, :show, user: updated_user)
        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render(:error, changeset: changeset)
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden"})
    end
  end

  # DELETE /api/v2/users/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)
    user = Accounts.get_user(id)

    cond do
      # Only admin can delete other users, users can delete themselves
      is_nil(user) ->
        conn
        |> put_status(:not_found)
        |> put_view(ErrorJSON)
        |> render("404.json")
      current_user.admin || current_user.id == user.id ->
        {:ok, _user} = Accounts.delete_user(user)
        send_resp(conn, :no_content, "")
      true ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})
    end
  end
end