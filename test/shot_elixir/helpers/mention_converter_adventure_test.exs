defmodule ShotElixir.Helpers.MentionConverterAdventureTest do
  use ShotElixir.DataCase, async: true
  import ShotElixir.Factory

  alias ShotElixir.Helpers.MentionConverter
  alias ShotElixir.Campaigns.Campaign

  describe "html_to_notion_rich_text with adventure description" do
    test "handles description with mentions" do
      campaign = insert(:campaign)

      # This is the actual description from the Yakuza Blues adventure
      html =
        ~s(<p>Here's <span class="Editor-module-scss-module__mofiSq__mention" data-type="mention" data-id="0c23290b-967e-4d51-bc34-23375be13515" data-label="Oyakawa Kojuro" data-mention-class-name="Character" data-mention-suggestion-char="@">@Oyakawa Kojuro</span> he's great with<span class="Editor-module-scss-module__mofiSq__mention" data-type="mention" data-id="a89bcbbf-4aaa-4823-903e-26870337681d" data-label="Fujiwara Akame" data-mention-class-name="Character" data-mention-suggestion-char="@">@Fujiwara Akame</span></p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      # Should not raise an error
      assert is_list(result)
    end

    test "handles nil description" do
      campaign = insert(:campaign)

      result = MentionConverter.html_to_notion_rich_text(nil, campaign)

      assert result == []
    end

    test "handles empty string description" do
      campaign = insert(:campaign)

      result = MentionConverter.html_to_notion_rich_text("", campaign)

      assert result == []
    end

    test "handles adjacent mentions without space" do
      campaign = insert(:campaign)

      # Two mentions with no text between them (but missing space in original)
      html =
        ~s(<p>Here's <span class="mention" data-type="mention" data-id="abc" data-label="Name1" data-mention-class-name="Character" data-mention-suggestion-char="@">@Name1</span><span class="mention" data-type="mention" data-id="def" data-label="Name2" data-mention-class-name="Character" data-mention-suggestion-char="@">@Name2</span></p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      # Should not raise an error
      assert is_list(result)
    end

    test "handles malformed mention spans" do
      campaign = insert(:campaign)

      # Partially matching span (missing data-mention-class-name)
      html =
        ~s(<p>Here's <span data-type="mention" data-id="abc" data-label="Name">@Name</span></p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      # Should not raise an error
      assert is_list(result)
    end

    test "handles Unicode characters in description" do
      campaign = insert(:campaign)

      html =
        ~s(<p>日本語 <span class="mention" data-type="mention" data-id="abc" data-label="小山田太郎" data-mention-class-name="Character" data-mention-suggestion-char="@">@小山田太郎</span></p>)

      result = MentionConverter.html_to_notion_rich_text(html, campaign)

      # Should not raise an error
      assert is_list(result)
    end
  end
end
