defmodule ShotElixirWeb.CampaignChannelTest do
  use ShotElixirWeb.ChannelCase
  import ShotElixir.Factory

  alias ShotElixirWeb.CampaignChannel
  alias ShotElixir.Guardian

  setup do
    user = insert(:user)
    campaign = insert(:campaign)
    insert(:campaign_user, user: user, campaign: campaign)

    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(ShotElixirWeb.UserSocket, %{"token" => token})
    {:ok, socket: socket, user: user, campaign: campaign}
  end

  describe "join/3" do
    test "authorized user can join campaign channel", %{socket: socket, campaign: campaign} do
      {:ok, reply, _socket} =
        subscribe_and_join(socket, CampaignChannel, "campaign:#{campaign.id}")

      assert reply == %{status: "ok"}
    end

    test "unauthorized user cannot join campaign channel", %{socket: socket} do
      other_campaign = insert(:campaign)

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, CampaignChannel, "campaign:#{other_campaign.id}")
    end

    test "invalid campaign ID returns error", %{socket: socket} do
      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, CampaignChannel, "campaign:invalid-id")
    end
  end

  describe "handle_info/2 - broadcast_update" do
    test "broadcasts update to all connected clients", %{socket: socket, campaign: campaign} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, CampaignChannel, "campaign:#{campaign.id}")

      # Simulate a broadcast
      CampaignChannel.broadcast_update(campaign.id, "test_event", %{data: "test"})

      assert_push "test_event", %{data: "test", timestamp: _}
    end

    test "broadcast includes timestamp", %{socket: socket, campaign: campaign} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, CampaignChannel, "campaign:#{campaign.id}")

      CampaignChannel.broadcast_update(campaign.id, "test_event", %{})

      assert_push "test_event", %{timestamp: timestamp}
      assert is_binary(timestamp) or is_struct(timestamp, DateTime)
    end
  end

  describe "broadcast_character_change/3" do
    test "broadcasts character created event", %{socket: socket, campaign: campaign} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, CampaignChannel, "campaign:#{campaign.id}")

      character = insert(:character, campaign: campaign)
      CampaignChannel.broadcast_character_change(campaign.id, character.id, "created")

      assert_push "character_created", %{
        character_id: character_id,
        action: "created",
        timestamp: _
      }

      assert character_id == character.id
    end

    test "broadcasts character updated event", %{socket: socket, campaign: campaign} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, CampaignChannel, "campaign:#{campaign.id}")

      character = insert(:character, campaign: campaign)
      CampaignChannel.broadcast_character_change(campaign.id, character.id, "updated")

      assert_push "character_updated", %{
        character_id: character_id,
        action: "updated",
        timestamp: _
      }

      assert character_id == character.id
    end

    test "broadcasts character deleted event", %{socket: socket, campaign: campaign} do
      {:ok, _reply, socket} =
        subscribe_and_join(socket, CampaignChannel, "campaign:#{campaign.id}")

      character = insert(:character, campaign: campaign)
      CampaignChannel.broadcast_character_change(campaign.id, character.id, "deleted")

      assert_push "character_deleted", %{
        character_id: character_id,
        action: "deleted",
        timestamp: _
      }

      assert character_id == character.id
    end
  end

  describe "authorization" do
    test "gamemaster can join any campaign channel", %{socket: socket} do
      gm_user = insert(:user, gamemaster: true)
      {:ok, token, _claims} = Guardian.encode_and_sign(gm_user)
      {:ok, gm_socket} = connect(ShotElixirWeb.UserSocket, %{"token" => token})

      other_campaign = insert(:campaign)

      {:ok, reply, _socket} =
        subscribe_and_join(gm_socket, CampaignChannel, "campaign:#{other_campaign.id}")

      assert reply == %{status: "ok"}
    end

    test "regular user needs campaign membership", %{socket: socket} do
      other_user = insert(:user)
      other_campaign = insert(:campaign)

      {:ok, token, _claims} = Guardian.encode_and_sign(other_user)
      {:ok, other_socket} = connect(ShotElixirWeb.UserSocket, %{"token" => token})

      # Without membership
      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(other_socket, CampaignChannel, "campaign:#{other_campaign.id}")

      # With membership
      insert(:campaign_user, user: other_user, campaign: other_campaign)

      {:ok, reply, _socket} =
        subscribe_and_join(other_socket, CampaignChannel, "campaign:#{other_campaign.id}")

      assert reply == %{status: "ok"}
    end
  end
end