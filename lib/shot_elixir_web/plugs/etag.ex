defmodule ShotElixirWeb.Plugs.ETag do
  @moduledoc """
  Utility module for ETag generation and validation.

  ETags enable HTTP conditional requests, allowing clients to skip
  downloading unchanged resources by returning 304 Not Modified.

  ## Usage

      alias ShotElixirWeb.Plugs.ETag

      def show(conn, %{"id" => id}) do
        character = Characters.get_character(id)
        etag = ETag.generate_etag(character)

        case ETag.check_stale(conn, etag) do
          {:not_modified, conn} ->
            conn
            |> ETag.put_etag(etag)
            |> send_resp(304, "")

          {:ok, conn} ->
            conn
            |> ETag.put_etag(etag)
            |> render("show.json", character: character)
        end
      end
  """
  import Plug.Conn

  @doc """
  Generates an ETag from a struct with `updated_at` and `id` fields.

  The ETag is an MD5 hash of the id and updated_at timestamp,
  providing a stable identifier that changes when the resource changes.

  Returns nil if the struct lacks required fields.

  ## Options

  - `:suffix` - Additional string to append to ETag source (e.g., for role-based variants)
  """
  @spec generate_etag(struct(), keyword()) :: String.t() | nil
  def generate_etag(entity, opts \\ [])

  def generate_etag(%{updated_at: updated_at, id: id}, opts) when not is_nil(updated_at) do
    suffix = Keyword.get(opts, :suffix, "")

    timestamp =
      case updated_at do
        %DateTime{} -> DateTime.to_unix(updated_at)
        %NaiveDateTime{} -> NaiveDateTime.to_gregorian_seconds(updated_at) |> elem(0)
        _ -> to_string(updated_at)
      end

    :crypto.hash(:md5, "#{id}-#{timestamp}-#{suffix}")
    |> Base.encode16(case: :lower)
  end

  def generate_etag(_, _), do: nil

  @doc """
  Checks if the client's If-None-Match header matches the current ETag.

  Returns:
  - `{:not_modified, conn}` if ETags match (client has current version)
  - `{:ok, conn}` if ETags don't match (client needs fresh data)
  """
  @spec check_stale(Plug.Conn.t(), String.t() | nil) :: {:ok | :not_modified, Plug.Conn.t()}
  def check_stale(conn, nil), do: {:ok, conn}

  def check_stale(conn, etag) do
    request_etag = get_req_header(conn, "if-none-match") |> List.first()

    if request_etag == "\"#{etag}\"" do
      {:not_modified, conn}
    else
      {:ok, conn}
    end
  end

  @doc """
  Adds an ETag header to the response.

  The ETag value is wrapped in quotes per HTTP spec.
  """
  @spec put_etag(Plug.Conn.t(), String.t() | nil) :: Plug.Conn.t()
  def put_etag(conn, nil), do: conn

  def put_etag(conn, etag) when is_binary(etag) do
    put_resp_header(conn, "etag", "\"#{etag}\"")
  end

  @doc """
  Wraps a response with HTTP caching (ETag + Cache-Control).

  This helper encapsulates the common pattern of:
  1. Generating an ETag from the entity
  2. Checking If-None-Match header
  3. Returning 304 if cached, or rendering with cache headers

  ## Options

  - `:cache_control` - The Cache-Control header value (required)

  ## Examples

      # In a controller action:
      ETag.with_caching(conn, site, cache_control: "private, max-age=60, must-revalidate", fn conn ->
        conn
        |> put_view(ShotElixirWeb.Api.V2.SiteView)
        |> render("show.json", site: site)
      end)

  """
  @spec with_caching(Plug.Conn.t(), struct(), keyword(), (Plug.Conn.t() -> Plug.Conn.t())) ::
          Plug.Conn.t()
  def with_caching(conn, entity, opts, render_fn) do
    cache_control = Keyword.fetch!(opts, :cache_control)
    etag = generate_etag(entity)

    case check_stale(conn, etag) do
      {:not_modified, conn} ->
        conn
        |> put_etag(etag)
        |> put_resp_header("cache-control", cache_control)
        |> send_resp(304, "")

      {:ok, conn} ->
        conn
        |> put_etag(etag)
        |> put_resp_header("cache-control", cache_control)
        |> render_fn.()
    end
  end
end
