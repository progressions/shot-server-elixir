defmodule ShotElixirWeb.AuthErrorHandler do
  import Plug.Conn
  require Logger

  @behaviour Guardian.Plug.ErrorHandler

  @impl Guardian.Plug.ErrorHandler
  def auth_error(conn, {type, reason}, _opts) do
    # Log detailed error for debugging
    Logger.warning(
      "[AuthErrorHandler] Auth error - type: #{inspect(type)}, reason: #{inspect(reason)}"
    )

    # Log the token header for debugging (truncated for security)
    auth_header = Plug.Conn.get_req_header(conn, "authorization") |> List.first()

    if auth_header do
      token_preview = String.slice(auth_header, 0, 30)
      Logger.info("[AuthErrorHandler] Token header present: #{token_preview}...")
    else
      Logger.info("[AuthErrorHandler] No authorization header present")
    end

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
