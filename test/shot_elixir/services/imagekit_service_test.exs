defmodule ShotElixir.Services.ImagekitServiceTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias ShotElixir.Services.ImagekitService

  describe "url/2" do
    test "generates URL with default transformation" do
      url = ImagekitService.url("test.jpg", %{})
      assert url =~ "https://ik.imagekit.io/"
      assert url =~ "/test.jpg"
    end

    test "generates URL with custom transformations" do
      url = ImagekitService.url("test.jpg", %{width: 300, height: 400, quality: 80})
      assert url =~ "tr:w-300,h-400,q-80"
      assert url =~ "/test.jpg"
    end

    test "generates URL with folder path" do
      url = ImagekitService.url("characters/test.jpg", %{})
      assert url =~ "/characters/test.jpg"
    end

    test "caches URL results" do
      url1 = ImagekitService.url("cached.jpg", %{width: 200})
      url2 = ImagekitService.url("cached.jpg", %{width: 200})
      assert url1 == url2
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
    test "returns error for invalid file_id" do
      assert {:error, _} = ImagekitService.delete_file(nil)
    end

    test "handles string file_id" do
      assert {:error, _} = ImagekitService.delete_file("test-file-id")
    end
  end

  describe "parse_upload_response/1" do
    test "parses successful upload response" do
      response = %{
        "fileId" => "12345",
        "name" => "test.jpg",
        "url" => "https://example.com/test.jpg",
        "thumbnailUrl" => "https://example.com/thumb.jpg",
        "height" => 600,
        "width" => 800,
        "size" => 50000
      }

      parsed = ImagekitService.parse_upload_response(response)

      assert parsed.file_id == "12345"
      assert parsed.name == "test.jpg"
      assert parsed.url == "https://example.com/test.jpg"
      assert parsed.thumbnail_url == "https://example.com/thumb.jpg"
      assert parsed.height == 600
      assert parsed.width == 800
      assert parsed.size == 50000
    end
  end

  describe "transformation_string/1" do
    test "builds transformation string from options" do
      str = ImagekitService.transformation_string(%{width: 300, height: 200, quality: 90})
      assert str == "tr:w-300,h-200,q-90"
    end

    test "handles empty options" do
      str = ImagekitService.transformation_string(%{})
      assert str == "tr:w-300,h-300,q-auto"
    end

    test "ignores unknown options" do
      str = ImagekitService.transformation_string(%{width: 100, unknown: "value"})
      assert str == "tr:w-100,h-300,q-auto"
    end
  end

  describe "auth_header/0" do
    test "generates base64 encoded auth header" do
      header = ImagekitService.auth_header()
      assert String.starts_with?(header, "Basic ")

      encoded = String.replace(header, "Basic ", "")
      decoded = Base.decode64!(encoded)
      assert String.contains?(decoded, ":")
    end
  end
end