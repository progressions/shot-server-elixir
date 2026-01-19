defmodule ShotElixirWeb.Plugs.ETagTest do
  @moduledoc """
  Tests for the ETag plug.
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixirWeb.Plugs.ETag

  describe "generate_etag/1" do
    test "generates etag from struct with DateTime updated_at" do
      entity = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        updated_at: ~U[2026-01-19 12:00:00Z]
      }

      etag = ETag.generate_etag(entity)

      assert is_binary(etag)
      assert String.length(etag) == 32
      # Verify it's hex-encoded
      assert String.match?(etag, ~r/^[a-f0-9]+$/)
    end

    test "generates etag from struct with NaiveDateTime updated_at" do
      entity = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        updated_at: ~N[2026-01-19 12:00:00]
      }

      etag = ETag.generate_etag(entity)

      assert is_binary(etag)
      assert String.length(etag) == 32
    end

    test "generates consistent etag for same input" do
      entity = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        updated_at: ~U[2026-01-19 12:00:00Z]
      }

      etag1 = ETag.generate_etag(entity)
      etag2 = ETag.generate_etag(entity)

      assert etag1 == etag2
    end

    test "generates different etag for different updated_at" do
      entity1 = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        updated_at: ~U[2026-01-19 12:00:00Z]
      }

      entity2 = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        updated_at: ~U[2026-01-19 12:00:01Z]
      }

      assert ETag.generate_etag(entity1) != ETag.generate_etag(entity2)
    end

    test "generates different etag for different id" do
      entity1 = %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        updated_at: ~U[2026-01-19 12:00:00Z]
      }

      entity2 = %{
        id: "550e8400-e29b-41d4-a716-446655440001",
        updated_at: ~U[2026-01-19 12:00:00Z]
      }

      assert ETag.generate_etag(entity1) != ETag.generate_etag(entity2)
    end

    test "returns nil when updated_at is nil" do
      entity = %{id: "550e8400-e29b-41d4-a716-446655440000", updated_at: nil}
      assert ETag.generate_etag(entity) == nil
    end

    test "returns nil when struct lacks required fields" do
      assert ETag.generate_etag(%{name: "test"}) == nil
      assert ETag.generate_etag(%{}) == nil
      assert ETag.generate_etag(nil) == nil
    end
  end

  describe "check_stale/2" do
    test "returns :ok when etag is nil" do
      conn = build_conn()
      assert {:ok, ^conn} = ETag.check_stale(conn, nil)
    end

    test "returns :ok when no If-None-Match header" do
      conn = build_conn()
      assert {:ok, ^conn} = ETag.check_stale(conn, "abc123")
    end

    test "returns :not_modified when ETags match" do
      conn =
        build_conn()
        |> put_req_header("if-none-match", "\"abc123\"")

      assert {:not_modified, ^conn} = ETag.check_stale(conn, "abc123")
    end

    test "returns :ok when ETags do not match" do
      conn =
        build_conn()
        |> put_req_header("if-none-match", "\"abc123\"")

      assert {:ok, ^conn} = ETag.check_stale(conn, "def456")
    end

    test "handles ETag without quotes in request header" do
      conn =
        build_conn()
        |> put_req_header("if-none-match", "abc123")

      # Should not match because our check expects quotes
      assert {:ok, ^conn} = ETag.check_stale(conn, "abc123")
    end
  end

  describe "put_etag/2" do
    test "adds etag header with quotes" do
      conn =
        build_conn()
        |> ETag.put_etag("abc123")

      assert get_resp_header(conn, "etag") == ["\"abc123\""]
    end

    test "returns conn unchanged when etag is nil" do
      conn = build_conn()
      result = ETag.put_etag(conn, nil)

      assert get_resp_header(result, "etag") == []
    end
  end
end
