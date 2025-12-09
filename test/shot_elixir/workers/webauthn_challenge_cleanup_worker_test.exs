defmodule ShotElixir.Workers.WebauthnChallengeCleanupWorkerTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Workers.WebauthnChallengeCleanupWorker
  alias ShotElixir.Accounts
  alias ShotElixir.Accounts.WebauthnChallenge

  @valid_user_attrs %{
    email: "cleanup-worker-test@example.com",
    password: "password123",
    first_name: "Test",
    last_name: "User"
  }

  describe "perform/1" do
    setup do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      %{user: user}
    end

    test "deletes used challenges", %{user: user} do
      # Create a used challenge
      {:ok, used_challenge} =
        %WebauthnChallenge{}
        |> WebauthnChallenge.create_changeset(%{
          user_id: user.id,
          challenge: :crypto.strong_rand_bytes(32),
          challenge_type: "registration"
        })
        |> Repo.insert()

      # Mark it as used
      used_challenge
      |> WebauthnChallenge.mark_used_changeset()
      |> Repo.update!()

      job = %Oban.Job{}

      assert :ok = WebauthnChallengeCleanupWorker.perform(job)

      # Challenge should be deleted
      assert Repo.get(WebauthnChallenge, used_challenge.id) == nil
    end

    test "deletes expired challenges", %{user: user} do
      # Create a challenge and manually set expires_at to past
      {:ok, challenge} =
        %WebauthnChallenge{}
        |> WebauthnChallenge.create_changeset(%{
          user_id: user.id,
          challenge: :crypto.strong_rand_bytes(32),
          challenge_type: "authentication"
        })
        |> Repo.insert()

      # Manually set expires_at to past
      past_time =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      challenge
      |> Ecto.Changeset.change(%{expires_at: past_time})
      |> Repo.update!()

      job = %Oban.Job{}

      assert :ok = WebauthnChallengeCleanupWorker.perform(job)

      # Challenge should be deleted
      assert Repo.get(WebauthnChallenge, challenge.id) == nil
    end

    test "deletes stale challenges older than 24 hours", %{user: user} do
      # Create a challenge
      {:ok, challenge} =
        %WebauthnChallenge{}
        |> WebauthnChallenge.create_changeset(%{
          user_id: user.id,
          challenge: :crypto.strong_rand_bytes(32),
          challenge_type: "registration"
        })
        |> Repo.insert()

      # Manually set inserted_at to more than 24 hours ago
      old_time = DateTime.add(DateTime.utc_now(), -25 * 3600, :second)

      Repo.update_all(
        from(c in WebauthnChallenge, where: c.id == ^challenge.id),
        set: [inserted_at: old_time]
      )

      job = %Oban.Job{}

      assert :ok = WebauthnChallengeCleanupWorker.perform(job)

      # Challenge should be deleted
      assert Repo.get(WebauthnChallenge, challenge.id) == nil
    end

    test "preserves valid unused challenges", %{user: user} do
      # Create a valid, unused challenge
      {:ok, valid_challenge} =
        %WebauthnChallenge{}
        |> WebauthnChallenge.create_changeset(%{
          user_id: user.id,
          challenge: :crypto.strong_rand_bytes(32),
          challenge_type: "registration"
        })
        |> Repo.insert()

      job = %Oban.Job{}

      assert :ok = WebauthnChallengeCleanupWorker.perform(job)

      # Challenge should still exist
      assert Repo.get(WebauthnChallenge, valid_challenge.id) != nil
    end

    test "handles multiple challenges correctly", %{user: user} do
      # Create a valid challenge (should be kept)
      {:ok, valid} =
        %WebauthnChallenge{}
        |> WebauthnChallenge.create_changeset(%{
          user_id: user.id,
          challenge: :crypto.strong_rand_bytes(32),
          challenge_type: "registration"
        })
        |> Repo.insert()

      # Create a used challenge (should be deleted)
      {:ok, used} =
        %WebauthnChallenge{}
        |> WebauthnChallenge.create_changeset(%{
          user_id: user.id,
          challenge: :crypto.strong_rand_bytes(32),
          challenge_type: "authentication"
        })
        |> Repo.insert()

      used
      |> WebauthnChallenge.mark_used_changeset()
      |> Repo.update!()

      # Create an expired challenge (should be deleted)
      {:ok, expired} =
        %WebauthnChallenge{}
        |> WebauthnChallenge.create_changeset(%{
          user_id: user.id,
          challenge: :crypto.strong_rand_bytes(32),
          challenge_type: "registration"
        })
        |> Repo.insert()

      past_time =
        DateTime.utc_now()
        |> DateTime.add(-3600, :second)
        |> DateTime.truncate(:second)

      expired
      |> Ecto.Changeset.change(%{expires_at: past_time})
      |> Repo.update!()

      job = %Oban.Job{}

      assert :ok = WebauthnChallengeCleanupWorker.perform(job)

      # Only valid should remain
      assert Repo.get(WebauthnChallenge, valid.id) != nil
      assert Repo.get(WebauthnChallenge, used.id) == nil
      assert Repo.get(WebauthnChallenge, expired.id) == nil
    end

    test "returns :ok even when no challenges exist" do
      job = %Oban.Job{}

      assert :ok = WebauthnChallengeCleanupWorker.perform(job)
    end
  end
end
