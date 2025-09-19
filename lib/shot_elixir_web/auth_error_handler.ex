defmodule ShotElixirWeb.AuthErrorHandler do
  import Plug.Conn

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    # Log the error for debugging
    IO.inspect({type, reason}, label: "Auth error")

    message =
      case {type, reason} do
        {:invalid_token, _} -> "Invalid token"
        {:unauthenticated, _} -> "Not authenticated"
        {:no_resource_found, _} -> "Not authenticated"
        _ -> "Not authenticated"
      end

    body = Jason.encode!(%{error: message})

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, body)
  end
end
