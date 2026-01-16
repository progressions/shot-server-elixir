defmodule ShotElixir.Helpers.MentionConverterTest do
  @moduledoc """
  Tests for bidirectional mention conversion between Chi War and Notion.
  """
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Helpers.MentionConverter
  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Characters.Character
  alias ShotElixir.Sites.Site
  alias ShotElixir.Parties.Party
  alias ShotElixir.Factions.Faction
  # These aliases are available if needed for additional tests:
  # alias ShotElixir.Junctures.Juncture
  # alias ShotElixir.Adventures.Adventure
  # alias ShotElixir.Vehicles.Vehicle

  setup do
    # Create user via Accounts.create_user which properly generates jti
    {:ok, user} =
      Accounts.create_user(%{
        email: "test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User"
      })

    {:ok, campaign} =
      %Campaign{}
      |> Campaign.changeset(%{name: "Test Campaign", user_id: user.id})
      |> Repo.insert()

    {:ok, user: user, campaign: campaign}
  end

  describe "html_to_notion_rich_text/2" do
    test "returns empty list for nil input", %{campaign: campaign} do
      assert MentionConverter.html_to_notion_rich_text(nil, campaign) == []
    end

    test "returns empty list for empty string", %{campaign: campaign} do
      assert MentionConverter.html_to_notion_rich_text("", campaign) == []
    end

    test "converts plain text without mentions", %{campaign: campaign} do
      html = "<p>Hello world</p>"
      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      assert length(result) == 1
      assert hd(result)["type"] == "text"
      assert hd(result)["text"]["content"] == "Hello world"
    end

    test "converts text with line breaks", %{campaign: campaign} do
      html = "<p>Line one</p><p>Line two</p>"
      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      assert length(result) == 1
      assert hd(result)["text"]["content"] == "Line one\nLine two"
    end

    test "converts mention with notion_page_id to page mention", %{campaign: campaign} do
      # Create a character with a notion_page_id
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Bob the Fighter",
          campaign_id: campaign.id,
          notion_page_id: "12345678-1234-1234-1234-123456789abc"
        })
        |> Repo.insert()

      html =
        ~s(<p>Hello <span data-type="mention" data-id="#{character.id}" data-label="Bob the Fighter" data-href="/characters/#{character.id}">@Bob the Fighter</span>!</p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      # Should have 3 elements: text, mention, text
      assert length(result) == 3
      assert Enum.at(result, 0)["type"] == "text"
      assert Enum.at(result, 0)["text"]["content"] == "Hello "
      assert Enum.at(result, 1)["type"] == "mention"
      assert Enum.at(result, 1)["mention"]["type"] == "page"
      assert Enum.at(result, 1)["mention"]["page"]["id"] == character.notion_page_id
      assert Enum.at(result, 2)["type"] == "text"
      assert Enum.at(result, 2)["text"]["content"] == "!"
    end

    test "converts mention without notion_page_id to URL link", %{campaign: campaign} do
      # Create a character without a notion_page_id
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Jane the Rogue",
          campaign_id: campaign.id
        })
        |> Repo.insert()

      html =
        ~s(<p>Meet <span data-type="mention" data-id="#{character.id}" data-label="Jane the Rogue" data-href="/characters/#{character.id}">@Jane the Rogue</span></p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      # Should have 2 elements: text, url link
      assert length(result) == 2
      assert Enum.at(result, 0)["type"] == "text"
      assert Enum.at(result, 0)["text"]["content"] == "Meet "
      assert Enum.at(result, 1)["type"] == "text"
      assert Enum.at(result, 1)["text"]["content"] == "@Jane the Rogue"
      assert Enum.at(result, 1)["text"]["link"]["url"] =~ "chiwar.net"
    end

    test "converts multiple mentions", %{campaign: campaign} do
      {:ok, char1} =
        %Character{}
        |> Character.changeset(%{
          name: "Alice",
          campaign_id: campaign.id,
          notion_page_id: "aaaaaaaa-1111-2222-3333-444444444444"
        })
        |> Repo.insert()

      {:ok, char2} =
        %Character{}
        |> Character.changeset(%{
          name: "Bob",
          campaign_id: campaign.id,
          notion_page_id: "bbbbbbbb-1111-2222-3333-444444444444"
        })
        |> Repo.insert()

      html =
        ~s(<p><span data-type="mention" data-id="#{char1.id}" data-label="Alice" data-href="/characters/#{char1.id}">@Alice</span> and <span data-type="mention" data-id="#{char2.id}" data-label="Bob" data-href="/characters/#{char2.id}">@Bob</span></p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      # Should have multiple elements including two page mentions
      mention_count = Enum.count(result, fn r -> r["type"] == "mention" end)
      assert mention_count == 2
    end

    test "converts Site mention", %{campaign: campaign} do
      {:ok, site} =
        %Site{}
        |> Site.changeset(%{
          name: "Dragon's Lair",
          campaign_id: campaign.id,
          notion_page_id: "12345678-site-site-site-123456789abc"
        })
        |> Repo.insert()

      html =
        ~s(<p>Located at <span data-type="mention" data-id="#{site.id}" data-label="Dragon's Lair" data-href="/sites/#{site.id}">@Dragon's Lair</span></p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      mention = Enum.find(result, fn r -> r["type"] == "mention" end)
      assert mention["mention"]["page"]["id"] == site.notion_page_id
    end

    test "converts Party mention", %{campaign: campaign} do
      {:ok, party} =
        %Party{}
        |> Party.changeset(%{
          name: "Dragon Hunters",
          campaign_id: campaign.id,
          notion_page_id: "12345678-pty0-pty0-pty0-123456789abc"
        })
        |> Repo.insert()

      html =
        ~s(<p>Join <span data-type="mention" data-id="#{party.id}" data-label="Dragon Hunters" data-href="/parties/#{party.id}">@Dragon Hunters</span></p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      mention = Enum.find(result, fn r -> r["type"] == "mention" end)
      assert mention["mention"]["page"]["id"] == party.notion_page_id
    end

    test "converts Faction mention", %{campaign: campaign} do
      {:ok, faction} =
        %Faction{}
        |> Faction.changeset(%{
          name: "The Ascended",
          campaign_id: campaign.id,
          notion_page_id: "12345678-fact-fact-fact-123456789abc"
        })
        |> Repo.insert()

      html =
        ~s(<p>Enemies of <span data-type="mention" data-id="#{faction.id}" data-label="The Ascended" data-href="/factions/#{faction.id}">@The Ascended</span></p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      mention = Enum.find(result, fn r -> r["type"] == "mention" end)
      assert mention["mention"]["page"]["id"] == faction.notion_page_id
    end
  end

  describe "notion_rich_text_to_html/2" do
    test "returns empty string for nil input", %{campaign: campaign} do
      assert MentionConverter.notion_rich_text_to_html(nil, campaign.id) == ""
    end

    test "returns empty string for empty list", %{campaign: campaign} do
      assert MentionConverter.notion_rich_text_to_html([], campaign.id) == ""
    end

    test "converts plain text", %{campaign: campaign} do
      rich_text = [%{"type" => "text", "text" => %{"content" => "Hello world"}}]
      result = MentionConverter.notion_rich_text_to_html(rich_text, campaign.id)

      assert result == "<p>Hello world</p>"
    end

    test "converts text with newlines to paragraphs", %{campaign: campaign} do
      rich_text = [%{"type" => "text", "text" => %{"content" => "Line one\nLine two"}}]
      result = MentionConverter.notion_rich_text_to_html(rich_text, campaign.id)

      assert result == "<p>Line one</p><p>Line two</p>"
    end

    test "converts page mention to Chi War mention span", %{campaign: campaign} do
      # Create a character with a notion_page_id
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Test Hero",
          campaign_id: campaign.id,
          notion_page_id: "abcd1234-5678-90ab-cdef-123456789abc"
        })
        |> Repo.insert()

      rich_text = [
        %{"type" => "text", "text" => %{"content" => "Hello "}},
        %{
          "type" => "mention",
          "mention" => %{
            "type" => "page",
            "page" => %{"id" => character.notion_page_id}
          }
        },
        %{"type" => "text", "text" => %{"content" => "!"}}
      ]

      result = MentionConverter.notion_rich_text_to_html(rich_text, campaign.id)

      assert result =~ "data-type=\"mention\""
      assert result =~ "data-id=\"#{character.id}\""
      assert result =~ "data-label=\"Test Hero\""
      assert result =~ "@Test Hero"
    end

    test "converts chiwar.net URL link to mention span", %{campaign: campaign} do
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "URL Hero",
          campaign_id: campaign.id
        })
        |> Repo.insert()

      rich_text = [
        %{
          "type" => "text",
          "text" => %{
            "content" => "@URL Hero",
            "link" => %{"url" => "https://chiwar.net/characters/#{character.id}"}
          }
        }
      ]

      result = MentionConverter.notion_rich_text_to_html(rich_text, campaign.id)

      assert result =~ "data-type=\"mention\""
      assert result =~ "data-id=\"#{character.id}\""
      assert result =~ "@URL Hero"
    end

    test "preserves external links as plain text", %{campaign: campaign} do
      rich_text = [
        %{
          "type" => "text",
          "text" => %{
            "content" => "Visit here",
            "link" => %{"url" => "https://example.com"}
          }
        }
      ]

      result = MentionConverter.notion_rich_text_to_html(rich_text, campaign.id)

      assert result == "<p>Visit here</p>"
      refute result =~ "data-type=\"mention\""
    end

    test "handles plain_text fallback format", %{campaign: campaign} do
      rich_text = [%{"plain_text" => "Simple text"}]
      result = MentionConverter.notion_rich_text_to_html(rich_text, campaign.id)

      assert result == "<p>Simple text</p>"
    end

    test "escapes HTML special characters", %{campaign: campaign} do
      rich_text = [%{"type" => "text", "text" => %{"content" => "2 < 3 & 3 > 2"}}]
      result = MentionConverter.notion_rich_text_to_html(rich_text, campaign.id)

      assert result =~ "&lt;"
      assert result =~ "&gt;"
      assert result =~ "&amp;"
    end
  end

  describe "extract_mentions/2" do
    test "returns empty list for text without mentions", %{campaign: campaign} do
      html = "<p>No mentions here</p>"
      result = MentionConverter.extract_mentions(html, campaign)

      assert result == []
    end

    test "extracts mention with all attributes", %{campaign: campaign} do
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Extracted Hero",
          campaign_id: campaign.id,
          notion_page_id: "e0000000-1234-5678-90ab-cdef12345678"
        })
        |> Repo.insert()

      html =
        ~s(<span data-type="mention" data-id="#{character.id}" data-label="Extracted Hero" data-href="/characters/#{character.id}">@Extracted Hero</span>)

      result = MentionConverter.extract_mentions(html, campaign)

      assert length(result) == 1
      mention = hd(result)
      assert mention.id == character.id
      assert mention.label == "Extracted Hero"
      assert mention.href == "/characters/#{character.id}"
      assert mention.entity_type == :character
      assert mention.notion_page_id == character.notion_page_id
    end

    test "extracts multiple mentions with positions", %{campaign: campaign} do
      {:ok, char1} =
        %Character{}
        |> Character.changeset(%{
          name: "First",
          campaign_id: campaign.id
        })
        |> Repo.insert()

      {:ok, char2} =
        %Character{}
        |> Character.changeset(%{
          name: "Second",
          campaign_id: campaign.id
        })
        |> Repo.insert()

      html =
        ~s(<span data-type="mention" data-id="#{char1.id}" data-label="First" data-href="/characters/#{char1.id}">@First</span> and <span data-type="mention" data-id="#{char2.id}" data-label="Second" data-href="/characters/#{char2.id}">@Second</span>)

      result = MentionConverter.extract_mentions(html, campaign)

      assert length(result) == 2
      assert Enum.at(result, 0).start_pos < Enum.at(result, 1).start_pos
    end
  end

  describe "lookup_entity_for_mention/3" do
    test "returns entity info for existing character", %{campaign: campaign} do
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Lookup Test",
          campaign_id: campaign.id,
          notion_page_id: "10000000-1234-5678-90ab-cdef12345678"
        })
        |> Repo.insert()

      result =
        MentionConverter.lookup_entity_for_mention(
          character.id,
          "/characters/#{character.id}",
          campaign
        )

      assert result.entity_type == :character
      assert result.notion_page_id == character.notion_page_id
    end

    test "returns nil notion_page_id for entity without one", %{campaign: campaign} do
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "No Notion",
          campaign_id: campaign.id
        })
        |> Repo.insert()

      result =
        MentionConverter.lookup_entity_for_mention(
          character.id,
          "/characters/#{character.id}",
          campaign
        )

      assert result.entity_type == :character
      assert result.notion_page_id == nil
    end

    test "returns nil for non-existent entity", %{campaign: campaign} do
      fake_id = Ecto.UUID.generate()

      result =
        MentionConverter.lookup_entity_for_mention(fake_id, "/characters/#{fake_id}", campaign)

      assert result.entity_type == :character
      assert result.notion_page_id == nil
    end

    test "returns nil entity_type for unknown href", %{campaign: campaign} do
      result = MentionConverter.lookup_entity_for_mention("some-id", "/unknown/some-id", campaign)

      assert result.entity_type == nil
      assert result.notion_page_id == nil
    end
  end

  describe "roundtrip conversion" do
    test "Chi War -> Notion -> Chi War preserves mentions", %{campaign: campaign} do
      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Roundtrip Hero",
          campaign_id: campaign.id,
          notion_page_id: "f0000000-1234-5678-90ab-cdef12345678"
        })
        |> Repo.insert()

      original_html =
        ~s(<p>Hello <span data-type="mention" data-id="#{character.id}" data-label="Roundtrip Hero" data-href="/characters/#{character.id}">@Roundtrip Hero</span>!</p>)

      # Convert to Notion
      notion_rich_text = MentionConverter.html_to_notion_rich_text(original_html, campaign)

      # Verify we have a page mention
      mention = Enum.find(notion_rich_text, fn r -> r["type"] == "mention" end)
      assert mention != nil
      assert mention["mention"]["page"]["id"] == character.notion_page_id

      # Convert back to HTML
      result_html = MentionConverter.notion_rich_text_to_html(notion_rich_text, campaign.id)

      # Should contain the mention span with correct attributes
      assert result_html =~ "data-type=\"mention\""
      assert result_html =~ "data-id=\"#{character.id}\""
      assert result_html =~ "@Roundtrip Hero"
    end
  end
end
