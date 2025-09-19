defmodule ShotElixir.Uploaders.ImageUploaderTest do
  use ExUnit.Case, async: true

  alias ShotElixir.Uploaders.ImageUploader
  alias ShotElixir.Characters.Character
  alias ShotElixir.Vehicles.Vehicle
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Sites.Site

  describe "validate/1" do
    test "accepts valid image types" do
      valid_types = [
        %{file_name: "test.jpg", path: "/tmp/test.jpg"},
        %{file_name: "test.jpeg", path: "/tmp/test.jpeg"},
        %{file_name: "test.png", path: "/tmp/test.png"},
        %{file_name: "test.gif", path: "/tmp/test.gif"},
        %{file_name: "test.webp", path: "/tmp/test.webp"}
      ]

      for file <- valid_types do
        assert ImageUploader.validate({file, %{}}) == :ok
      end
    end

    test "rejects invalid file types" do
      invalid_types = [
        %{file_name: "test.txt", path: "/tmp/test.txt"},
        %{file_name: "test.pdf", path: "/tmp/test.pdf"},
        %{file_name: "test.doc", path: "/tmp/test.doc"}
      ]

      for file <- invalid_types do
        assert {:error, "Invalid file type"} = ImageUploader.validate({file, %{}})
      end
    end

    test "rejects files without extension" do
      file = %{file_name: "test", path: "/tmp/test"}
      assert {:error, "Invalid file type"} = ImageUploader.validate({file, %{}})
    end
  end

  describe "folder_for_scope/1" do
    test "returns correct folder for Character" do
      character = %Character{id: "abc123"}
      assert ImageUploader.folder_for_scope(character) == "/characters"
    end

    test "returns correct folder for Vehicle" do
      vehicle = %Vehicle{id: "def456"}
      assert ImageUploader.folder_for_scope(vehicle) == "/vehicles"
    end

    test "returns correct folder for Faction" do
      faction = %Faction{id: "ghi789"}
      assert ImageUploader.folder_for_scope(faction) == "/factions"
    end

    test "returns correct folder for Site" do
      site = %Site{id: "jkl012"}
      assert ImageUploader.folder_for_scope(site) == "/sites"
    end

    test "returns default folder for unknown scope" do
      unknown = %{id: "xyz"}
      assert ImageUploader.folder_for_scope(unknown) == "/uploads"
    end
  end

  describe "tags_for_scope/1" do
    test "includes scope type and ID in tags for Character" do
      character = %Character{id: "abc123"}
      tags = ImageUploader.tags_for_scope(character)

      assert Enum.member?(tags, "character")
      assert Enum.member?(tags, "character_abc123")
    end

    test "includes scope type and ID in tags for Vehicle" do
      vehicle = %Vehicle{id: "def456"}
      tags = ImageUploader.tags_for_scope(vehicle)

      assert Enum.member?(tags, "vehicle")
      assert Enum.member?(tags, "vehicle_def456")
    end

    test "includes default tag for unknown scope" do
      unknown = %{id: "xyz"}
      tags = ImageUploader.tags_for_scope(unknown)

      assert tags == ["upload"]
    end
  end

  describe "storage_dir/2" do
    test "returns ImageKit folder structure" do
      file = %{file_name: "test.jpg"}
      character = %Character{id: "abc123"}

      dir = ImageUploader.storage_dir(:original, {file, character})
      assert dir == "/characters"
    end
  end

  describe "filename/2" do
    test "generates unique filename with timestamp" do
      file = %{file_name: "test.jpg"}
      character = %Character{id: "abc123"}

      filename = ImageUploader.filename(:original, {file, character})

      assert filename =~ ~r/^\d+_test\.jpg$/
      assert String.ends_with?(filename, "_test.jpg")
    end

    test "preserves file extension" do
      file = %{file_name: "image.png"}
      character = %Character{id: "abc123"}

      filename = ImageUploader.filename(:original, {file, character})
      assert String.ends_with?(filename, ".png")
    end

    test "handles files with multiple dots" do
      file = %{file_name: "my.image.name.jpg"}
      character = %Character{id: "abc123"}

      filename = ImageUploader.filename(:original, {file, character})
      assert String.ends_with?(filename, "_my.image.name.jpg")
    end
  end
end