defmodule ShotElixir.Services.ImagekitServiceTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias ShotElixir.Services.ImagekitService

  describe "generate_url/2" do
    test "generates URL with default transformation" do
      url = ImagekitService.generate_url("test.jpg", [])
      assert url =~ "https://ik.imagekit.io/"
      assert url =~ "/test.jpg"
    end

    test "generates URL with custom transformations" do
      url = ImagekitService.generate_url("test.jpg", [%{height: 300, width: 400}])
      assert url =~ "tr:h-300,w-400"
      assert url =~ "/test.jpg"
    end

    test "generates URL with folder path" do
      url = ImagekitService.generate_url("characters/test.jpg", [])
      assert url =~ "/characters/test.jpg"
    end

    test "generates URL with multiple transformations" do
      transforms = [
        %{height: 500, width: 500},
        %{quality: 90}
      ]
      url = ImagekitService.generate_url("test.jpg", transforms)
      assert url =~ "tr:"
      assert url =~ "/test.jpg"
    end
  end

  describe "upload_file/2" do
    test "handles file upload with valid parameters" do
      assert {:error, _} = ImagekitService.upload_file("/nonexistent/file.jpg", %{})
    end

    test "validates file existence" do
      result = ImagekitService.upload_file("/invalid/path.jpg", %{})
      assert {:error, :enoent} = result
    end
  end

  describe "delete_file/1" do
    test "handles string file_id" do
      # Set minimal config to avoid runtime error
      Application.put_env(:shot_elixir, :imagekit, [
        private_key: "test_private_key",
        public_key: "test_public_key",
        url_endpoint: "https://ik.imagekit.io/test"
      ])

      assert {:error, _} = ImagekitService.delete_file("test-file-id")
    end
  end

  describe "generate_url_from_metadata/1" do
    test "generates URL from metadata with name" do
      metadata = %{"name" => "uploaded-image.jpg"}
      url = ImagekitService.generate_url_from_metadata(metadata)
      assert url =~ "uploaded-image.jpg"
    end

    test "generates URL from metadata with fileId and name" do
      metadata = %{"fileId" => "abc123", "name" => "uploaded-image.jpg"}
      url = ImagekitService.generate_url_from_metadata(metadata)
      assert url =~ "uploaded-image.jpg"
    end

    test "returns nil for invalid metadata" do
      assert nil == ImagekitService.generate_url_from_metadata(%{})
      assert nil == ImagekitService.generate_url_from_metadata(%{"other" => "data"})
    end
  end
end