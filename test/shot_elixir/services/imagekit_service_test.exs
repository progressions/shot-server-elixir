defmodule ShotElixir.Services.ImagekitServiceTest do
  use ExUnit.Case, async: true

  alias ShotElixir.Services.ImagekitService

  describe "generate_url/2" do
    test "generates basic URL without transformations" do
      url = ImagekitService.generate_url("test-image.jpg", [])
      assert url =~ "https://ik.imagekit.io/"
      assert url =~ "test-image.jpg"
    end

    test "generates URL with transformations" do
      url = ImagekitService.generate_url("test-image.jpg", [%{height: 300, width: 300}])
      assert url =~ "https://ik.imagekit.io/"
      assert url =~ "tr:h-300,w-300"
      assert url =~ "test-image.jpg"
    end

    test "generates URL with multiple transformations" do
      transforms = [
        %{height: 500, width: 500},
        %{quality: 90}
      ]
      url = ImagekitService.generate_url("test-image.jpg", transforms)
      assert url =~ "tr:"
      assert url =~ "test-image.jpg"
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

  # Note: These tests would require mocking the HTTP client
  # or using a test mode that doesn't make real API calls

  @tag :skip
  describe "upload_file/2" do
    test "uploads a file successfully" do
      # This would require a mock or test file
      # and mocked HTTP responses
    end
  end

  @tag :skip
  describe "delete_file/1" do
    test "deletes a file successfully" do
      # This would require mocking the delete API call
    end
  end
end