defmodule ShotElixir.Services.Notion.BlocksGmOnlyTest do
  @moduledoc """
  Tests for splitting Notion blocks at "GM Only" heading.

  The `split_at_gm_only_heading/1` function splits a list of Notion blocks
  into public content and GM-only content based on the presence of a
  Heading 1 block with text "GM Only".
  """
  use ExUnit.Case, async: true

  alias ShotElixir.Services.Notion.Blocks

  describe "split_at_gm_only_heading/1" do
    test "splits blocks at 'GM Only' heading" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [%{"plain_text" => "Public paragraph 1"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [%{"plain_text" => "Public paragraph 2"}]
          }
        },
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "GM Only"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{
            "rich_text" => [%{"plain_text" => "Secret paragraph for GM"}]
          }
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      assert length(public_blocks) == 2
      assert length(gm_only_blocks) == 1

      assert Enum.at(gm_only_blocks, 0)["paragraph"]["rich_text"] |> hd() |> Map.get("plain_text") ==
               "Secret paragraph for GM"
    end

    test "case-insensitive match for 'gm only'" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Public"}]}
        },
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "gm only"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Secret"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      assert length(public_blocks) == 1
      assert length(gm_only_blocks) == 1
    end

    test "handles 'GM ONLY' in all caps" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Public"}]}
        },
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "GM ONLY"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Secret"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      assert length(public_blocks) == 1
      assert length(gm_only_blocks) == 1
    end

    test "handles 'Gm Only' mixed case" do
      blocks = [
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "Gm Only"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Secret"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      assert length(public_blocks) == 0
      assert length(gm_only_blocks) == 1
    end

    test "trims whitespace from heading text" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Public"}]}
        },
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "  GM Only  "}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Secret"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      assert length(public_blocks) == 1
      assert length(gm_only_blocks) == 1
    end

    test "returns all blocks as public when no 'GM Only' heading exists" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Paragraph 1"}]}
        },
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "Regular Heading"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Paragraph 2"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      assert length(public_blocks) == 3
      assert gm_only_blocks == []
    end

    test "returns empty public blocks when 'GM Only' is at the start" do
      blocks = [
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "GM Only"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "All content is secret"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      assert public_blocks == []
      assert length(gm_only_blocks) == 1
    end

    test "splits at first 'GM Only' heading when multiple exist" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Public"}]}
        },
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "GM Only"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Secret 1"}]}
        },
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "GM Only"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Secret 2"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      assert length(public_blocks) == 1
      # Includes everything after first GM Only heading (including second GM Only heading)
      assert length(gm_only_blocks) == 3
    end

    test "only matches heading_1 type, not heading_2 or heading_3" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Public"}]}
        },
        %{
          "type" => "heading_2",
          "heading_2" => %{
            "rich_text" => [%{"plain_text" => "GM Only"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Still public"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      # heading_2 is not matched, so all content is public
      assert length(public_blocks) == 3
      assert gm_only_blocks == []
    end

    test "handles empty blocks list" do
      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading([])

      assert public_blocks == []
      assert gm_only_blocks == []
    end

    test "handles heading with multiple rich_text segments" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Public"}]}
        },
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [
              %{"plain_text" => "GM "},
              %{"plain_text" => "Only"}
            ]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Secret"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      assert length(public_blocks) == 1
      assert length(gm_only_blocks) == 1
    end

    test "does not match partial 'GM Only' text" do
      blocks = [
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Public"}]}
        },
        %{
          "type" => "heading_1",
          "heading_1" => %{
            "rich_text" => [%{"plain_text" => "GM Only Notes"}]
          }
        },
        %{
          "type" => "paragraph",
          "paragraph" => %{"rich_text" => [%{"plain_text" => "Still public"}]}
        }
      ]

      {public_blocks, gm_only_blocks} = Blocks.split_at_gm_only_heading(blocks)

      # "GM Only Notes" is not exact match for "GM Only", so all content is public
      assert length(public_blocks) == 3
      assert gm_only_blocks == []
    end
  end
end
