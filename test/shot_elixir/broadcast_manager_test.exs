defmodule ShotElixir.BroadcastManagerTest do
  use ShotElixir.DataCase

  alias ShotElixir.BroadcastManager
  alias ShotElixir.{Accounts, Repo}
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Characters.Character

  describe "broadcast_entity_change/2" do
    test "broadcasts update payloads and reload signal" do
      character = insert_character()
      topic = "campaign:#{character.campaign_id}"

      :ok = Phoenix.PubSub.subscribe(ShotElixir.PubSub, topic)
      flush_messages()

      assert :ok = BroadcastManager.broadcast_entity_change(character, :update)

      assert_receive {:rails_message, %{"character" => payload}}, 1_000
      assert payload["id"] == character.id
      assert payload["entity_class"] == "Character"

      assert_receive {:rails_message, %{"characters" => "reload"}}, 1_000
    end

    test "broadcasts only reload on delete" do
      character = insert_character()
      topic = "campaign:#{character.campaign_id}"

      :ok = Phoenix.PubSub.subscribe(ShotElixir.PubSub, topic)
      flush_messages()

      assert :ok = BroadcastManager.broadcast_entity_change(character, :delete)

      assert_receive {:rails_message, %{"characters" => "reload"}}, 1_000
      refute_receive {:rails_message, %{"character" => _}}, 100
    end
  end

  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end

  defp insert_character do
    {:ok, user} =
      Accounts.create_user(%{
        email: "user-#{System.unique_integer([:positive])}@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User"
      })

    {:ok, campaign} =
      %Campaign{}
      |> Campaign.changeset(%{name: "Test Campaign", description: "", user_id: user.id})
      |> Repo.insert()

    {:ok, character} =
      %Character{}
      |> Character.changeset(%{
        name: "Test Character",
        campaign_id: campaign.id,
        user_id: user.id,
        action_values: %{"Type" => "PC"}
      })
      |> Repo.insert()

    character
  end
end
