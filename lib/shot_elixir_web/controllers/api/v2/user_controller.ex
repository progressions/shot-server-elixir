defmodule ShotElixirWeb.Api.V2.UserController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/users
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Authorization: admin or gamemaster for campaign queries
    authorized =
      cond do
        current_user.admin ->
          :admin

        current_user.gamemaster && params["campaign_id"] ->
          case Campaigns.get_campaign(params["campaign_id"]) do
            nil ->
              :forbidden

            campaign ->
              if campaign.user_id == current_user.id do
                :gamemaster
              else
                :forbidden
              end
          end

        true ->
          :forbidden
      end

    case authorized do
      :forbidden ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Forbidden"})

      _ ->
        result = Accounts.list_campaign_users(params, current_user)
        render(conn, :index, data: result)
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
      conn
      |> put_view(ShotElixirWeb.Api.V2.UserView)
      |> render("current.json", user: user)
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
                user =
                  user
                  |> ShotElixir.Repo.preload([:current_campaign, :campaigns, :player_campaigns])

                render(conn, :profile, user: user)
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Forbidden"})
          end

        _ ->
          # Accessing own profile - always allowed
          user =
            current_user
            |> ShotElixir.Repo.preload([:current_campaign, :campaigns, :player_campaigns])

          render(conn, :profile, user: user)
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Not authenticated"})
    end
  end

  # POST /api/v2/users - Public registration endpoint
  def create(conn, user_params) do
    # Handle JSON string parsing like Rails
    parsed_params =
      case user_params do
        %{"user" => user_data} when is_binary(user_data) ->
          case Jason.decode(user_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid user data format"})
              |> halt()
          end

        %{"user" => user_data} when is_map(user_data) ->
          user_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "User parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      case Accounts.create_user(parsed_params) do
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
  end

  # POST /api/v2/users/register (public endpoint)
  def register(conn, user_params) do
    # Handle JSON string parsing like Rails
    parsed_params =
      case user_params do
        %{"user" => user_data} when is_binary(user_data) ->
          case Jason.decode(user_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid user data format"})
              |> halt()
          end

        %{"user" => user_data} when is_map(user_data) ->
          user_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "User parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      # Set gamemaster to true by default like Rails
      final_params =
        Map.put(parsed_params, "gamemaster", Map.get(parsed_params, "gamemaster", true))

      case Accounts.create_user(final_params) do
        {:ok, user} ->
          {:ok, token, claims} = Guardian.encode_and_sign(user)

          conn
          |> put_status(:created)
          |> put_resp_header("authorization", "Bearer #{token}")
          |> json(%{
            code: 201,
            message: "Registration successful. Please check your email to confirm your account.",
            data: render_user_data(user),
            payload: claims
          })

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render(:error, changeset: changeset)
      end
    end
  end

  # PATCH/PUT /api/v2/users/:id
  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Accounts.get_user(params["id"]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Record not found"})

      user ->
        # Check authorization - only admin or self can update
        if current_user.admin || current_user.id == user.id do
          # Handle JSON string parsing like Rails
          parsed_params =
            case params do
              %{"user" => user_data} when is_binary(user_data) ->
                case Jason.decode(user_data) do
                  {:ok, decoded} ->
                    decoded

                  {:error, _} ->
                    conn
                    |> put_status(:bad_request)
                    |> json(%{error: "Invalid user data format"})
                    |> halt()
                end

              %{"user" => user_data} when is_map(user_data) ->
                user_data

              _ ->
                conn
                |> put_status(:bad_request)
                |> json(%{error: "User parameters required"})
                |> halt()
            end

          if conn.halted do
            conn
          else
            case Accounts.update_user(user, parsed_params) do
              {:ok, updated_user} ->
                {:ok, token, _claims} = Guardian.encode_and_sign(updated_user)

                conn
                |> put_resp_header("authorization", "Bearer #{token}")
                |> render(:show, user: updated_user)

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> render(:error, changeset: changeset)
            end
          end
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Forbidden"})
        end
    end
  end

  # PATCH /api/v2/users/profile
  def update_profile(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Handle JSON string parsing like Rails
    parsed_params =
      case params do
        %{"user" => user_data} when is_binary(user_data) ->
          case Jason.decode(user_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid user data format"})
              |> halt()
          end

        %{"user" => user_data} when is_map(user_data) ->
          user_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "User parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      case Accounts.update_user(current_user, parsed_params) do
        {:ok, updated_user} ->
          {:ok, token, _claims} = Guardian.encode_and_sign(updated_user)

          conn
          |> put_resp_header("authorization", "Bearer #{token}")
          |> render(:show, user: updated_user)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> render(:error, changeset: changeset)
      end
    end
  end

  # DELETE /api/v2/users/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Admin can delete any user, users can delete themselves
    unless current_user.admin || current_user.id == id do
      conn
      |> put_status(:forbidden)
      |> json(%{error: "Forbidden"})
    else
      case Accounts.get_user(id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Record not found"})

        user ->
          {:ok, _user} = Accounts.delete_user(user)
          send_resp(conn, :no_content, "")
      end
    end
  end

  # DELETE /api/v2/users/:id/remove_image
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Accounts.get_user(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Record not found"})

      user ->
        # Only admin or self can remove image
        if current_user.admin || current_user.id == user.id do
          # TODO: Implement image removal when Active Storage equivalent is added
          # For now, just return success
          {:ok, token, _claims} = Guardian.encode_and_sign(user)

          conn
          |> put_resp_header("authorization", "Bearer #{token}")
          |> render(:show, user: user)
        else
          conn
          |> put_status(:forbidden)
          |> json(%{error: "Admin access required to remove another user's image"})
        end
    end
  end

  # Helper function for rendering user data in register response
  defp render_user_data(user) do
    %{
      id: user.id,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      name: user.name,
      admin: user.admin,
      gamemaster: user.gamemaster,
      active: user.active,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end
end
