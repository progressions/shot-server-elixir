defmodule ShotElixirWeb.Plugs.CacheControlTest do
  @moduledoc """
  Tests for the CacheControl plug.
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixirWeb.Plugs.CacheControl

  describe "init/1" do
    test "returns options unchanged" do
      opts = [max_age: 60, private: true]
      assert CacheControl.init(opts) == opts
    end
  end

  describe "call/2" do
    test "sets default cache-control header" do
      conn =
        build_conn()
        |> CacheControl.call([])
        |> send_resp(200, "")

      assert get_resp_header(conn, "cache-control") == ["private, max-age=0, must-revalidate"]
    end

    test "sets custom max_age" do
      conn =
        build_conn()
        |> CacheControl.call(max_age: 3600)
        |> send_resp(200, "")

      assert get_resp_header(conn, "cache-control") == ["private, max-age=3600, must-revalidate"]
    end

    test "sets public cache-control when private is false" do
      conn =
        build_conn()
        |> CacheControl.call(private: false, max_age: 60)
        |> send_resp(200, "")

      assert get_resp_header(conn, "cache-control") == ["public, max-age=60, must-revalidate"]
    end

    test "omits must-revalidate when must_revalidate is false" do
      conn =
        build_conn()
        |> CacheControl.call(max_age: 60, must_revalidate: false)
        |> send_resp(200, "")

      assert get_resp_header(conn, "cache-control") == ["private, max-age=60"]
    end

    test "combines all options correctly" do
      conn =
        build_conn()
        |> CacheControl.call(max_age: 120, private: false, must_revalidate: true)
        |> send_resp(200, "")

      assert get_resp_header(conn, "cache-control") == ["public, max-age=120, must-revalidate"]
    end
  end
end
