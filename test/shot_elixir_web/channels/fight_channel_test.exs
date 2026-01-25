defmodule ShotElixirWeb.FightChannelTest do
  use ShotElixirWeb.ChannelCase, async: true
  import ShotElixir.Factory

  alias ShotElixirWeb.{FightChannel, Presence}
  alias ShotElixir.Guardian

  setup do
    user = insert(:user)
    campaign = insert(:campaign)
    insert(:campaign_user, user: user, campaign: campaign)
    fight = insert(:fight, campaign: campaign)

    {:ok, token, _claims} = Guardian.encode_and_sign(user)
    {:ok, socket} = connect(ShotElixirWeb.UserSocket, %{"token" => token})
    {:ok, socket: socket, user: user, campaign: campaign, fight: fight}
  end

  describe "join/3" do
    test "authorized user can join fight channel", %{socket: socket, fight: fight} do
      {:ok, reply, socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      assert %{status: "ok", fight_id: fight_id} = reply
      assert fight_id == fight.id

      # Check presence tracking
      assert %{} != Presence.list(socket)
    end

    test "unauthorized user cannot join fight channel", %{socket: socket} do
      other_campaign = insert(:campaign)
      other_fight = insert(:fight, campaign: other_campaign)

      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, FightChannel, "fight:#{other_fight.id}")
    end

    test "invalid fight ID returns error", %{socket: socket} do
      assert {:error, %{reason: "unauthorized"}} =
               subscribe_and_join(socket, FightChannel, "fight:invalid-id")
    end

    test "tracks user presence on join", %{socket: socket, fight: fight, user: user} do
      {:ok, _reply, socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      # Give presence time to sync
      :timer.sleep(10)

      presences = Presence.list(socket)
      assert Map.has_key?(presences, user.id)

      user_presence = presences[user.id]
      assert user_presence.metas != []

      [meta | _] = user_presence.metas
      assert meta.user_id == user.id
      assert meta.user_name
      assert meta.joined_at
    end
  end

  describe "handle_in/3 - shot_update" do
    test "broadcasts shot update to all clients", %{socket: socket, fight: fight} do
      {:ok, _reply, socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      shot = insert(:shot, fight: fight)

      payload = %{
        "shot_id" => shot.id,
        "updates" => %{
          "shot" => 10,
          "acted" => false
        }
      }

      ref = push(socket, "shot_update", payload)
      assert_reply ref, :ok

      assert_broadcast "shot_updated", broadcast_payload
      assert broadcast_payload["shot"]["id"] == shot.id
      assert broadcast_payload["shot"]["shot_number"] == 10
      assert broadcast_payload["shot"]["acted"] == false
    end

    test "includes timestamp in shot update broadcast", %{socket: socket, fight: fight} do
      {:ok, _reply, socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      shot = insert(:shot, fight: fight)

      payload = %{
        "shot_id" => shot.id,
        "updates" => %{"shot" => 10}
      }

      ref = push(socket, "shot_update", payload)
      assert_reply ref, :ok

      assert_broadcast "shot_updated", broadcast_payload
      refute is_nil(broadcast_payload["updated_by"])
    end
  end

  describe "handle_in/3 - character_action" do
    test "broadcasts character action to all clients", %{socket: socket, fight: fight} do
      {:ok, _reply, socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      character = insert(:character)

      payload = %{
        "character_id" => character.id,
        "action" => "attack"
      }

      ref = push(socket, "character_act", payload)
      assert_reply ref, :ok

      assert_broadcast "character_acted", broadcast_payload
      assert broadcast_payload["character_id"] == character.id
      assert broadcast_payload["action"] == "attack"
      assert broadcast_payload["acted_by"]
      assert broadcast_payload["timestamp"]
    end
  end

  describe "handle_in/3 - sync_request" do
    test "replies with current fight state", %{socket: socket, fight: fight} do
      {:ok, _reply, socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      ref = push(socket, "sync_request", %{})

      assert_reply ref, :ok, reply
      assert reply["fight_id"] == fight.id
      assert Map.has_key?(reply, "timestamp")
    end
  end

  describe "broadcast_fight_update/2" do
    test "broadcasts fight updates to channel", %{socket: socket, fight: fight} do
      {:ok, _reply, socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      FightChannel.broadcast_fight_update(fight.id, "fight_update", %{
        event: "round_advanced",
        round: 2
      })

      assert_push "fight_update", %{
        event: "round_advanced",
        round: 2,
        timestamp: _
      }
    end
  end

  describe "presence tracking" do
    test "removes user from presence on leave", %{socket: socket, fight: fight, user: user} do
      {:ok, _reply, socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      # Verify user is present
      :timer.sleep(10)
      presences = Presence.list(socket)
      assert Map.has_key?(presences, user.id)

      # Leave channel
      Process.unlink(socket.channel_pid)
      ref = leave(socket)
      assert_reply ref, :ok

      # Verify user is removed from presence
      :timer.sleep(10)
      presences_after = Presence.list("fight:#{fight.id}")
      refute Map.has_key?(presences_after, user.id)
    end

    test "tracks multiple users in same fight", %{fight: fight, campaign: campaign} do
      user1 = insert(:user)
      user2 = insert(:user)

      insert(:campaign_user, user: user1, campaign: campaign)
      insert(:campaign_user, user: user2, campaign: campaign)

      {:ok, token1, _} = Guardian.encode_and_sign(user1)
      {:ok, token2, _} = Guardian.encode_and_sign(user2)

      {:ok, socket1} = connect(ShotElixirWeb.UserSocket, %{"token" => token1})
      {:ok, socket2} = connect(ShotElixirWeb.UserSocket, %{"token" => token2})

      {:ok, _reply, socket1} = subscribe_and_join(socket1, FightChannel, "fight:#{fight.id}")
      {:ok, _reply, socket2} = subscribe_and_join(socket2, FightChannel, "fight:#{fight.id}")

      :timer.sleep(10)
      presences = Presence.list(socket1)

      assert Map.has_key?(presences, user1.id)
      assert Map.has_key?(presences, user2.id)
    end
  end

  describe "authorization" do
    test "gamemaster can join any fight channel", %{socket: socket} do
      gm_user = insert(:user, gamemaster: true)
      {:ok, token, _claims} = Guardian.encode_and_sign(gm_user)
      {:ok, gm_socket} = connect(ShotElixirWeb.UserSocket, %{"token" => token})

      other_campaign = insert(:campaign)
      other_fight = insert(:fight, campaign: other_campaign)

      {:ok, reply, _socket} =
        subscribe_and_join(gm_socket, FightChannel, "fight:#{other_fight.id}")

      assert %{status: "ok"} = reply
    end
  end

  describe "location broadcasts" do
    test "broadcast_location_created sends location data", %{socket: socket, fight: fight} do
      {:ok, _reply, _socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      location = insert(:location, fight: fight, name: "The Rooftop")

      FightChannel.broadcast_location_created(fight.id, location)

      assert_push "location_created", payload
      assert payload.location.id == location.id
      assert payload.location.name == "The Rooftop"
      assert payload.location.fight_id == fight.id
    end

    test "broadcast_location_updated sends updated location data", %{socket: socket, fight: fight} do
      {:ok, _reply, _socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      location = insert(:location, fight: fight, name: "The Basement")

      FightChannel.broadcast_location_updated(fight.id, location)

      assert_push "location_updated", payload
      assert payload.location.id == location.id
      assert payload.location.name == "The Basement"
    end

    test "broadcast_location_deleted sends location_id", %{socket: socket, fight: fight} do
      {:ok, _reply, _socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      location = insert(:location, fight: fight)

      FightChannel.broadcast_location_deleted(fight.id, location.id)

      assert_push "location_deleted", payload
      assert payload.location_id == location.id
    end

    test "broadcast_shot_location_changed sends shot and location info", %{
      socket: socket,
      fight: fight
    } do
      {:ok, _reply, _socket} = subscribe_and_join(socket, FightChannel, "fight:#{fight.id}")

      location = insert(:location, fight: fight, name: "The Alley")
      character = insert(:character)
      shot = insert(:shot, fight: fight, character: character, location_id: location.id)
      shot = ShotElixir.Repo.preload(shot, :location_ref)

      FightChannel.broadcast_shot_location_changed(fight.id, shot)

      assert_push "shot_location_changed", payload
      assert payload.shot_id == shot.id
      assert payload.location_id == location.id
      assert payload.location_name == "The Alley"
    end
  end
end
