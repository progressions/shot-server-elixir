defmodule ShotElixir.AsNotionHtmlStrippingTest do
  @moduledoc """
  Tests for HTML stripping in as_notion functions across all entity types.

  When syncing descriptions to Notion, HTML tags should be stripped and
  converted to plain text with appropriate newlines for paragraph and
  line breaks.
  """
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Sites.Site
  alias ShotElixir.Parties.Party
  alias ShotElixir.Factions.Faction
  alias ShotElixir.Adventures.Adventure
  alias ShotElixir.Junctures.Juncture
  alias ShotElixir.Characters.Character

  describe "Site.as_notion/1 HTML stripping" do
    test "strips HTML tags from description" do
      site = %Site{
        name: "Test Site",
        description: "<p>This is a <strong>test</strong> site.</p>",
        at_a_glance: false
      }

      result = Site.as_notion(site)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "This is a test site."
    end

    test "converts paragraph tags to newlines" do
      site = %Site{
        name: "Test Site",
        description: "<p>First paragraph.</p><p>Second paragraph.</p>",
        at_a_glance: false
      }

      result = Site.as_notion(site)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "First paragraph.\nSecond paragraph."
    end

    test "converts br tags to newlines" do
      site = %Site{
        name: "Test Site",
        description: "Line one<br>Line two<br/>Line three",
        at_a_glance: false
      }

      result = Site.as_notion(site)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "Line one\nLine two\nLine three"
    end

    test "handles nil description" do
      site = %Site{
        name: "Test Site",
        description: nil,
        at_a_glance: false
      }

      result = Site.as_notion(site)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == ""
    end

    test "handles plain text description without HTML" do
      site = %Site{
        name: "Test Site",
        description: "Just plain text",
        at_a_glance: false
      }

      result = Site.as_notion(site)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "Just plain text"
    end
  end

  describe "Party.as_notion/1 HTML stripping" do
    test "strips HTML tags from description" do
      party = %Party{
        name: "Test Party",
        description: "<p>A group of <em>heroes</em>.</p>",
        at_a_glance: false
      }

      result = Party.as_notion(party)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "A group of heroes."
    end

    test "converts paragraph tags to newlines" do
      party = %Party{
        name: "Test Party",
        description: "<p>Dragon Hunters</p><p>Based in Hong Kong</p>",
        at_a_glance: false
      }

      result = Party.as_notion(party)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "Dragon Hunters\nBased in Hong Kong"
    end

    test "handles nil description" do
      party = %Party{
        name: "Test Party",
        description: nil,
        at_a_glance: false
      }

      result = Party.as_notion(party)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == ""
    end
  end

  describe "Faction.as_notion/1 HTML stripping" do
    test "strips HTML tags from description" do
      faction = %Faction{
        name: "Test Faction",
        description: "<p>An <strong>evil</strong> organization.</p>",
        at_a_glance: false
      }

      result = Faction.as_notion(faction)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "An evil organization."
    end

    test "converts paragraph tags to newlines" do
      faction = %Faction{
        name: "Test Faction",
        description: "<p>The Ascended</p><p>Masters of the Secret War</p>",
        at_a_glance: false
      }

      result = Faction.as_notion(faction)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "The Ascended\nMasters of the Secret War"
    end

    test "handles nil description" do
      faction = %Faction{
        name: "Test Faction",
        description: nil,
        at_a_glance: false
      }

      result = Faction.as_notion(faction)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == ""
    end
  end

  describe "Adventure.as_notion/1 HTML stripping" do
    test "strips HTML tags from description" do
      adventure = %Adventure{
        name: "Test Adventure",
        description: "<p>A <strong>dangerous</strong> mission.</p>",
        at_a_glance: false
      }

      result = Adventure.as_notion(adventure)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "A dangerous mission."
    end

    test "converts paragraph tags to newlines" do
      adventure = %Adventure{
        name: "Test Adventure",
        description: "<p>Episode One</p><p>The heroes begin their journey</p>",
        at_a_glance: false
      }

      result = Adventure.as_notion(adventure)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "Episode One\nThe heroes begin their journey"
    end

    test "handles nil description" do
      adventure = %Adventure{
        name: "Test Adventure",
        description: nil,
        at_a_glance: false
      }

      result = Adventure.as_notion(adventure)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == ""
    end
  end

  describe "Juncture.as_notion/1 HTML stripping" do
    test "strips HTML tags from description" do
      juncture = %Juncture{
        name: "Test Juncture",
        description: "<p>The <em>modern</em> era.</p>",
        at_a_glance: false
      }

      result = Juncture.as_notion(juncture)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "The modern era."
    end

    test "converts paragraph tags to newlines" do
      juncture = %Juncture{
        name: "Test Juncture",
        description: "<p>Contemporary Era</p><p>1996-Present Day</p>",
        at_a_glance: false
      }

      result = Juncture.as_notion(juncture)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "Contemporary Era\n1996-Present Day"
    end

    test "handles nil description" do
      juncture = %Juncture{
        name: "Test Juncture",
        description: nil,
        at_a_glance: false
      }

      result = Juncture.as_notion(juncture)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == ""
    end
  end

  describe "Character.as_notion/1 HTML stripping" do
    test "strips HTML from Melodramatic Hook" do
      character = %Character{
        name: "Test Character",
        description: %{
          "Melodramatic Hook" => "<p>Seeks <strong>revenge</strong> for father's death.</p>"
        },
        action_values: %{"Type" => "PC"}
      }

      result = Character.as_notion(character)
      hook_content = get_in(result, ["Melodramatic Hook", "rich_text", Access.at(0), "text", "content"])

      assert hook_content == "Seeks revenge for father's death."
    end

    test "strips HTML from Appearance (Description field)" do
      character = %Character{
        name: "Test Character",
        description: %{
          "Appearance" => "<p>Tall and <em>imposing</em>.</p>"
        },
        action_values: %{"Type" => "PC"}
      }

      result = Character.as_notion(character)
      desc_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert desc_content == "Tall and imposing."
    end

    test "converts paragraph tags to newlines in description fields" do
      character = %Character{
        name: "Test Character",
        description: %{
          "Melodramatic Hook" => "<p>First hook line.</p><p>Second hook line.</p>"
        },
        action_values: %{"Type" => "PC"}
      }

      result = Character.as_notion(character)
      hook_content = get_in(result, ["Melodramatic Hook", "rich_text", Access.at(0), "text", "content"])

      assert hook_content == "First hook line.\nSecond hook line."
    end
  end

  describe "complex HTML scenarios" do
    test "handles nested HTML tags" do
      site = %Site{
        name: "Test Site",
        description: "<p><strong><em>Bold italic</em></strong> text.</p>",
        at_a_glance: false
      }

      result = Site.as_notion(site)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "Bold italic text."
    end

    test "handles unordered lists" do
      site = %Site{
        name: "Test Site",
        description: "<ul><li>Item one</li><li>Item two</li></ul>",
        at_a_glance: false
      }

      result = Site.as_notion(site)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      # HTML tags are stripped, list items become plain text
      assert description_content == "Item oneItem two"
    end

    test "handles mixed content with links" do
      site = %Site{
        name: "Test Site",
        description: "<p>Visit <a href=\"https://example.com\">here</a> for more.</p>",
        at_a_glance: false
      }

      result = Site.as_notion(site)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "Visit here for more."
    end

    test "trims whitespace from result" do
      site = %Site{
        name: "Test Site",
        description: "   <p>  Spaced content  </p>   ",
        at_a_glance: false
      }

      result = Site.as_notion(site)
      description_content = get_in(result, ["Description", "rich_text", Access.at(0), "text", "content"])

      assert description_content == "Spaced content"
    end
  end
end
