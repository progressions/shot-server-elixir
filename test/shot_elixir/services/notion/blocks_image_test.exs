defmodule ShotElixir.Services.Notion.BlocksImageTest do
  use ExUnit.Case, async: true

  alias ShotElixir.Services.Notion.Blocks

  test "renders image markdown using imported URLs" do
    block = %{
      "id" => "block-1",
      "type" => "image",
      "image" => %{
        "caption" => [%{"type" => "text", "text" => %{"content" => "Alt text"}}]
      }
    }

    image_urls = %{"block-1" => "https://ik.imagekit.io/test/image.jpg"}

    {markdown, mentions} = Blocks.blocks_to_markdown([block], "campaign-id", nil, image_urls)

    assert markdown == "![Alt text](https://ik.imagekit.io/test/image.jpg)"
    assert mentions == %{}
  end
end
