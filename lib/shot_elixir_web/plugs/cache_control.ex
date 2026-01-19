defmodule ShotElixirWeb.Plugs.CacheControl do
  @moduledoc """
  Plug for setting Cache-Control headers on responses.

  ## Usage

  In a router pipeline:

      plug ShotElixirWeb.Plugs.CacheControl, max_age: 3600, private: false

  In a controller (requires import or alias):

      alias ShotElixirWeb.Plugs.CacheControl
      plug CacheControl, max_age: 60, private: true when action in [:show]

  ## Options

  - `:max_age` - The max-age directive in seconds (default: 0)
  - `:private` - Whether the cache should be private (default: true)
  - `:must_revalidate` - Whether must-revalidate should be added (default: true)
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    max_age = Keyword.get(opts, :max_age, 0)
    private = Keyword.get(opts, :private, true)
    must_revalidate = Keyword.get(opts, :must_revalidate, true)

    directive = if private, do: "private", else: "public"

    header =
      [directive, "max-age=#{max_age}"]
      |> maybe_add_must_revalidate(must_revalidate)
      |> Enum.join(", ")

    register_before_send(conn, fn conn ->
      put_resp_header(conn, "cache-control", header)
    end)
  end

  defp maybe_add_must_revalidate(directives, true), do: directives ++ ["must-revalidate"]
  defp maybe_add_must_revalidate(directives, false), do: directives
end
