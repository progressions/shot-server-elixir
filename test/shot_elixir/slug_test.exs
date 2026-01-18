defmodule ShotElixir.SlugTest do
  use ExUnit.Case, async: true

  alias ShotElixir.Slug

  describe "extract_uuid/1" do
    test "returns bare uuid unchanged" do
      uuid = "123e4567-e89b-12d3-a456-426614174000"
      assert Slug.extract_uuid(uuid) == uuid
    end

    test "extracts uuid from slugged string" do
      uuid = "123e4567-e89b-12d3-a456-426614174000"
      assert Slug.extract_uuid("cool-character-#{uuid}") == uuid
      assert Slug.extract_uuid("cool-character-with-dashes-#{uuid}") == uuid
    end

    test "falls back to input when no uuid present" do
      assert Slug.extract_uuid("not-a-uuid") == "not-a-uuid"
    end

    test "ignores empty and invalid uuid-like strings" do
      assert Slug.extract_uuid("") == ""

      assert Slug.extract_uuid("123e4567-e89b-12d3-a456-42661417400Z") ==
               "123e4567-e89b-12d3-a456-42661417400Z"
    end

    test "handles long strings with trailing uuid" do
      uuid = "123e4567-e89b-12d3-a456-426614174000"
      prefix = String.duplicate("prefix-", 10)
      assert Slug.extract_uuid(prefix <> uuid) == uuid
    end
  end

  describe "slugify_name/1" do
    test "hyphenates and lowercases" do
      assert Slug.slugify_name("Cool Character") == "cool-character"
    end

    test "strips punctuation and compresses separators" do
      assert Slug.slugify_name("  Hello,   World!!  ") == "hello-world"
    end

    test "returns empty string for nil" do
      assert Slug.slugify_name(nil) == ""
    end

    test "strips accents and emoji to ascii-safe slug" do
      assert Slug.slugify_name("Café Society") == "cafe-society"
      assert Slug.slugify_name("Dragon 🐉 Style!") == "dragon-style"
    end

    test "returns empty string when everything is stripped" do
      assert Slug.slugify_name("!!!") == ""
    end
  end

  describe "slugged_id/2" do
    test "combines slug and id" do
      uuid = "123e4567-e89b-12d3-a456-426614174000"
      assert Slug.slugged_id("Cool Character", uuid) == "cool-character-" <> uuid
    end

    test "falls back to id when name missing" do
      uuid = "123e4567-e89b-12d3-a456-426614174000"
      assert Slug.slugged_id(nil, uuid) == uuid
    end
  end
end
