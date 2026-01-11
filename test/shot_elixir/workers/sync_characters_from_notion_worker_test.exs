defmodule ShotElixir.Workers.SyncCharactersFromNotionWorkerTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Workers.SyncCharactersFromNotionWorker
  alias ShotElixir.Characters
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Accounts

  describe "get_notion_linked_characters/0" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-periodic-sync@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Periodic Sync Test Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "returns only characters with notion_page_id set", %{campaign: campaign} do
      # Create a character WITH notion_page_id
      {:ok, linked_character} =
        Characters.create_character(%{
          name: "Linked Character",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      # Create a character WITHOUT notion_page_id
      {:ok, _unlinked_character} =
        Characters.create_character(%{
          name: "Unlinked Character",
          campaign_id: campaign.id
        })

      result = SyncCharactersFromNotionWorker.get_notion_linked_characters()

      # Should only include the linked character
      assert length(result) >= 1
      assert Enum.any?(result, fn c -> c.id == linked_character.id end)
    end

    test "excludes inactive characters", %{campaign: campaign} do
      # Create an inactive character with notion_page_id
      {:ok, inactive_character} =
        Characters.create_character(%{
          name: "Inactive Linked Character",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate(),
          active: false
        })

      result = SyncCharactersFromNotionWorker.get_notion_linked_characters()

      # Should not include inactive character
      refute Enum.any?(result, fn c -> c.id == inactive_character.id end)
    end

    test "returns characters ordered by updated_at", %{campaign: campaign} do
      # Create multiple linked characters
      {:ok, char1} =
        Characters.create_character(%{
          name: "First Character",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      # Small delay to ensure different timestamps
      Process.sleep(10)

      {:ok, char2} =
        Characters.create_character(%{
          name: "Second Character",
          campaign_id: campaign.id,
          notion_page_id: Ecto.UUID.generate()
        })

      result = SyncCharactersFromNotionWorker.get_notion_linked_characters()

      # Find positions of our characters
      char1_index = Enum.find_index(result, fn c -> c.id == char1.id end)
      char2_index = Enum.find_index(result, fn c -> c.id == char2.id end)

      # Ensure both characters are present in the result before comparing positions
      refute is_nil(char1_index)
      refute is_nil(char2_index)

      # char1 should come before char2 (ordered by updated_at asc)
      assert char1_index < char2_index
    end
  end

  describe "perform/1" do
    test "returns :ok in test environment (skips actual sync)" do
      # In test environment, should skip the sync
      job = %Oban.Job{args: %{}}
      assert :ok = SyncCharactersFromNotionWorker.perform(job)
    end
  end

  describe "sync_all_linked_characters/0" do
    test "returns summary with zero counts when no characters to sync" do
      # With no notion-linked characters, should return empty summary
      {:ok, summary} = SyncCharactersFromNotionWorker.sync_all_linked_characters()

      assert summary.total == 0
      assert summary.success == 0
      assert summary.errors == 0
    end

    test "returns {:ok, summary} tuple with expected keys" do
      {:ok, summary} = SyncCharactersFromNotionWorker.sync_all_linked_characters()

      assert is_map(summary)
      assert Map.has_key?(summary, :total)
      assert Map.has_key?(summary, :success)
      assert Map.has_key?(summary, :errors)
    end
  end
end
