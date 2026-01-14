defmodule ShotElixirWeb.Plugs.VerifyTokenParam do
  @moduledoc """
  A plug that extracts JWT tokens from query parameters.
  Used for OAuth flows where browser redirects can't include Authorization headers.

  Usage in router:
      plug ShotElixirWeb.Plugs.VerifyTokenParam
  """
  alias ShotElixir.Guardian

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.query_params["token"] do
      nil ->
        conn

      token ->
        case Guardian.decode_and_verify(token) do
          {:ok, claims} ->
            case Guardian.resource_from_claims(claims) do
              {:ok, resource} ->
                conn
                |> Guardian.Plug.put_current_resource(resource)
                |> Guardian.Plug.put_current_claims(claims)
                |> Guardian.Plug.put_current_token(token)

              {:error, _reason} ->
                conn
            end

          {:error, _reason} ->
            conn
        end
    end
  end
end
