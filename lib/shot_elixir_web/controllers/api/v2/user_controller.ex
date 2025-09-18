defmodule ShotElixirWeb.Api.V2.UserController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Accounts.User

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/users
  def index(conn, _params) do
    users = Accounts.list_users()
    render(conn, "index.json", users: users)
  end

  # GET /api/v2/users/:id
  def show(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)
    render(conn, "show.json", user: user)
  end

  # GET /api/v2/users/current
  def current(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    if user do
      # Preload associations if needed
      user = user |> ShotElixir.Repo.preload([:current_campaign, :campaigns, :player_campaigns])
      render(conn, "current.json", user: user)
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Not authenticated"})
    end
  end

  # GET /api/v2/users/profile
  def profile(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    if user do
      user = user |> ShotElixir.Repo.preload([:current_campaign, :campaigns, :player_campaigns])
      render(conn, "profile.json", user: user)
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
        render(conn, "show.json", user: updated_user)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", changeset: changeset)
    end
  end

  # POST /api/v2/users
  def create(conn, %{"user" => user_params}) do
    case Accounts.create_user(user_params) do
      {:ok, user} ->
        {:ok, token, _claims} = ShotElixir.Guardian.encode_and_sign(user)

        conn
        |> put_status(:created)
        |> put_resp_header("authorization", "Bearer #{token}")
        |> render("show.json", user: user, token: token)
      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render("error.json", changeset: changeset)
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
          render(conn, "show.json", user: updated_user)
        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render("error.json", changeset: changeset)
      end
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Not authorized"})
    end
  end

  # DELETE /api/v2/users/:id
  def delete(conn, %{"id" => id}) do
    user = Accounts.get_user!(id)
    current_user = Guardian.Plug.current_resource(conn)

    # Only admin can delete users
    if current_user.admin do
      {:ok, _user} = Accounts.delete_user(user)
      send_resp(conn, :no_content, "")
    else
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Not authorized"})
    end
  end
end