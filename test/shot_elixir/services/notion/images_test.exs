defmodule ShotElixir.Services.Notion.ImagesTest do
  use ExUnit.Case, async: true

  alias ShotElixir.Services.Notion.Images

  defmodule NotionClientStub do
    def get_block_children(block_id, opts \\ [])
    def get_block_children("parent-1", _opts) do
      %{
        "results" => [
          %{
            "id" => "child-1",
            "type" => "image",
            "image" => %{
              "type" => "external",
              "external" => %{"url" => "https://foo.notion.so/child.jpg"}
            }
          }
        ]
      }
    end

    def get_block_children(_, _opts), do: %{"results" => []}
  end

  defmodule RepoStub do
    def get_by(_schema, _opts), do: nil
    def insert(_changeset), do: {:ok, :mapping}
  end

  setup do
    original_imagekit_config = Application.get_env(:shot_elixir, :imagekit)

    Application.put_env(:shot_elixir, :notion_client, NotionClientStub)
    Application.put_env(:shot_elixir, :imagekit,
      private_key: "test_private_key",
      public_key: "test_public_key",
      url_endpoint: "https://ik.imagekit.io/test",
      disabled: true
    )

    on_exit(fn ->
      restore_env(:notion_client, nil)
      restore_env(:imagekit, original_imagekit_config)
    end)

    :ok
  end

  test "imports nested child images by fetching children" do
    block = %{"id" => "parent-1", "type" => "bulleted_list_item", "has_children" => true}

    image_urls = Images.import_block_images("page-1", [block], "token", repo: RepoStub)

    assert image_urls["child-1"] ==
             "https://ik.imagekit.io/test/chi-war-test/notion/child-1.jpg"
  end

  defp restore_env(_key, nil), do: :ok
  defp restore_env(key, value), do: Application.put_env(:shot_elixir, key, value)
end
