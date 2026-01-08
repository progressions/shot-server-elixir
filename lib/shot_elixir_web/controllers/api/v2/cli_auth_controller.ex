defmodule ShotElixirWeb.Api.V2.CliAuthController do
  @moduledoc """
  Controller for CLI device authorization flow.

  Flow:
  1. CLI calls `start` to get a code
  2. CLI opens browser to /cli/auth?code=XXX
  3. User approves in browser (calls `approve`)
  4. CLI polls `poll` until approved, then gets JWT token
  """

  use ShotElixirWeb, :controller

  alias ShotElixir.Accounts
  alias ShotElixirWeb.AuthHelpers

  action_fallback ShotElixirWeb.FallbackController

  @frontend_url Application.compile_env(:shot_elixir, :frontend_url, "https://chiwar.net")

  @doc """
  Starts a new CLI authorization session.
  Returns a code and URL for the user to approve.
  """
  def start(conn, _params) do
    case Accounts.create_cli_auth_code() do
      {:ok, auth_code} ->
        url = "#{@frontend_url}/cli/auth?code=#{auth_code.code}"
        expires_in = DateTime.diff(auth_code.expires_at, DateTime.utc_now())

        conn
        |> put_status(:ok)
        |> json(%{
          code: auth_code.code,
          url: url,
          expires_in: expires_in
        })

      {:error, _changeset} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to create authorization code"})
    end
  end

  @doc """
  Polls for authorization status.
  Returns pending, approved (with token), or expired.
  """
  def poll(conn, %{"code" => code}) do
    case Accounts.poll_cli_auth_code(code) do
      {:pending, expires_in} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "pending", expires_in: expires_in})

      {:approved, user} ->
        {token, _claims} = Accounts.generate_auth_token(user)

        conn
        |> put_status(:ok)
        |> json(%{
          status: "approved",
          token: token,
          user: AuthHelpers.render_user(user)
        })

      {:error, :expired} ->
        conn
        |> put_status(:gone)
        |> json(%{status: "expired", error: "Authorization code expired"})
    end
  end

  def poll(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing code parameter"})
  end

  @doc """
  Approves a CLI authorization code.
  Requires authentication.
  """
  def approve(conn, %{"code" => code}) do
    user = Guardian.Plug.current_resource(conn)

    case Accounts.approve_cli_auth_code(code, user) do
      {:ok, _auth_code} ->
        conn
        |> put_status(:ok)
        |> json(%{success: true})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Authorization code not found or expired"})

      {:error, :already_approved} ->
        conn
        |> put_status(:conflict)
        |> json(%{error: "Authorization code already approved"})

      {:error, _changeset} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "Failed to approve authorization code"})
    end
  end

  def approve(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing code parameter"})
  end
end
