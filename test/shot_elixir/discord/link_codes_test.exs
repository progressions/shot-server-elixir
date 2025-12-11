defmodule ShotElixir.Discord.LinkCodesTest do
  use ExUnit.Case, async: false
  alias ShotElixir.Discord.LinkCodes

  setup do
    # Ensure the LinkCodes agent is running (it may be started by the application)
    case Process.whereis(LinkCodes) do
      nil ->
        {:ok, _pid} = LinkCodes.start_link([])

      _pid ->
        # Agent is already running, clear its state for a fresh test
        Agent.update(LinkCodes, fn _state -> %{} end)
    end

    :ok
  end

  describe "generate/2" do
    test "generates a 6-character uppercase alphanumeric code" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"

      code = LinkCodes.generate(discord_id, discord_username)

      assert is_binary(code)
      assert String.length(code) == 6
      assert code =~ ~r/^[A-Z0-9]+$/
    end

    test "removes existing codes for the same Discord user" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"

      code1 = LinkCodes.generate(discord_id, discord_username)
      code2 = LinkCodes.generate(discord_id, discord_username)

      # First code should no longer be valid
      assert {:error, :invalid_code} = LinkCodes.validate(code1)
      # Second code should be valid
      assert {:ok, _data} = LinkCodes.validate(code2)
    end

    test "generates unique codes for different users" do
      code1 = LinkCodes.generate(111_111_111_111_111_111, "user1")
      code2 = LinkCodes.generate(222_222_222_222_222_222, "user2")

      refute code1 == code2
    end
  end

  describe "validate/1" do
    test "returns ok with data for valid code" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"
      code = LinkCodes.generate(discord_id, discord_username)

      assert {:ok, data} = LinkCodes.validate(code)
      assert data.discord_id == discord_id
      assert data.discord_username == discord_username
      assert %DateTime{} = data.expires_at
    end

    test "is case insensitive" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"
      code = LinkCodes.generate(discord_id, discord_username)

      assert {:ok, _data} = LinkCodes.validate(String.downcase(code))
      assert {:ok, _data} = LinkCodes.validate(String.upcase(code))
    end

    test "returns error for invalid code" do
      assert {:error, :invalid_code} = LinkCodes.validate("INVALID")
    end

    test "returns error for expired code" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"
      code = LinkCodes.generate(discord_id, discord_username)

      # Manually expire the code
      Agent.update(LinkCodes, fn state ->
        Map.update!(state, code, fn data ->
          %{data | expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)}
        end)
      end)

      assert {:error, :expired} = LinkCodes.validate(code)
    end
  end

  describe "consume/1" do
    test "removes a valid code" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"
      code = LinkCodes.generate(discord_id, discord_username)

      # Code should be valid
      assert {:ok, _data} = LinkCodes.validate(code)

      # Consume the code
      :ok = LinkCodes.consume(code)

      # Code should no longer be valid
      assert {:error, :invalid_code} = LinkCodes.validate(code)
    end

    test "is case insensitive" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"
      code = LinkCodes.generate(discord_id, discord_username)

      :ok = LinkCodes.consume(String.downcase(code))

      assert {:error, :invalid_code} = LinkCodes.validate(code)
    end

    test "handles non-existent code gracefully" do
      # Should not raise an error
      :ok = LinkCodes.consume("NONEXISTENT")
    end
  end

  describe "cleanup_expired/0" do
    test "removes expired codes" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"
      code = LinkCodes.generate(discord_id, discord_username)

      # Manually expire the code
      Agent.update(LinkCodes, fn state ->
        Map.update!(state, code, fn data ->
          %{data | expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)}
        end)
      end)

      # Code should return expired error before cleanup
      assert {:error, :expired} = LinkCodes.validate(code)

      # Run cleanup
      LinkCodes.cleanup_expired()

      # Code should now be completely gone (invalid, not expired)
      assert {:error, :invalid_code} = LinkCodes.validate(code)
    end

    test "keeps non-expired codes" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"
      code = LinkCodes.generate(discord_id, discord_username)

      LinkCodes.cleanup_expired()

      assert {:ok, _data} = LinkCodes.validate(code)
    end
  end
end
