defmodule ShotElixir.Workers.LinkCodeCleanupWorkerTest do
  use ExUnit.Case, async: false
  alias ShotElixir.Workers.LinkCodeCleanupWorker
  alias ShotElixir.Discord.LinkCodes

  setup do
    # Ensure the LinkCodes agent is running
    case Process.whereis(LinkCodes) do
      nil ->
        {:ok, _pid} = LinkCodes.start_link([])

      _pid ->
        # Agent is already running, clear its state for a fresh test
        Agent.update(LinkCodes, fn _state -> %{} end)
    end

    :ok
  end

  describe "perform/1" do
    test "cleans up expired codes" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"

      # Generate a code
      code = LinkCodes.generate(discord_id, discord_username)

      # Manually expire the code
      Agent.update(LinkCodes, fn state ->
        Map.update!(state, code, fn data ->
          %{data | expires_at: DateTime.add(DateTime.utc_now(), -1, :hour)}
        end)
      end)

      # Verify code is expired but still in state
      assert {:error, :expired} = LinkCodes.validate(code)

      # Run the worker
      job = %Oban.Job{}
      assert :ok = LinkCodeCleanupWorker.perform(job)

      # Code should now be completely gone
      assert {:error, :invalid_code} = LinkCodes.validate(code)
    end

    test "keeps non-expired codes" do
      discord_id = 123_456_789_012_345_678
      discord_username = "testuser"
      code = LinkCodes.generate(discord_id, discord_username)

      # Run the worker
      job = %Oban.Job{}
      assert :ok = LinkCodeCleanupWorker.perform(job)

      # Code should still be valid
      assert {:ok, _data} = LinkCodes.validate(code)
    end

    test "handles empty state gracefully" do
      # Run the worker with no codes in the agent
      job = %Oban.Job{}
      assert :ok = LinkCodeCleanupWorker.perform(job)
    end
  end
end
