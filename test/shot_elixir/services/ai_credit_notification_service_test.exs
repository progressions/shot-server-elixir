defmodule ShotElixir.Services.AiCreditNotificationServiceTest do
  use ShotElixir.DataCase, async: true
  use Oban.Testing, repo: ShotElixir.Repo

  alias ShotElixir.Services.AiCreditNotificationService
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Accounts

  describe "handle_credit_exhaustion/3" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-credit-test@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Credit Test Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "updates campaign exhaustion fields for grok provider", %{campaign: campaign, user: user} do
      assert {:ok, :handled} =
               AiCreditNotificationService.handle_credit_exhaustion(campaign.id, user.id, "grok")

      updated = Repo.get(Campaign, campaign.id)
      assert updated.ai_credits_exhausted_at != nil
      assert updated.ai_credits_exhausted_provider == "grok"
    end

    test "updates campaign exhaustion fields for openai provider", %{
      campaign: campaign,
      user: user
    } do
      assert {:ok, :handled} =
               AiCreditNotificationService.handle_credit_exhaustion(
                 campaign.id,
                 user.id,
                 "openai"
               )

      updated = Repo.get(Campaign, campaign.id)
      assert updated.ai_credits_exhausted_at != nil
      assert updated.ai_credits_exhausted_provider == "openai"
    end

    test "updates campaign exhaustion fields for gemini provider", %{
      campaign: campaign,
      user: user
    } do
      assert {:ok, :handled} =
               AiCreditNotificationService.handle_credit_exhaustion(
                 campaign.id,
                 user.id,
                 "gemini"
               )

      updated = Repo.get(Campaign, campaign.id)
      assert updated.ai_credits_exhausted_at != nil
      assert updated.ai_credits_exhausted_provider == "gemini"
    end

    test "returns error when campaign not found", %{user: user} do
      fake_id = Ecto.UUID.generate()

      assert {:error, :campaign_not_found} =
               AiCreditNotificationService.handle_credit_exhaustion(fake_id, user.id, "grok")
    end

    test "broadcasts credit status to campaign channel for grok", %{
      campaign: campaign,
      user: user
    } do
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      # Use manual mode to prevent email worker jobs from executing
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, :handled} =
                 AiCreditNotificationService.handle_credit_exhaustion(
                   campaign.id,
                   user.id,
                   "grok"
                 )

        assert_receive {:campaign_broadcast, payload}
        assert payload.campaign.is_ai_credits_exhausted == true
        assert payload.campaign.ai_credits_exhausted_provider == "grok"
      end)
    end

    test "broadcasts credit status to campaign channel for openai", %{
      campaign: campaign,
      user: user
    } do
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{campaign.id}")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, :handled} =
                 AiCreditNotificationService.handle_credit_exhaustion(
                   campaign.id,
                   user.id,
                   "openai"
                 )

        assert_receive {:campaign_broadcast, payload}
        assert payload.campaign.is_ai_credits_exhausted == true
        assert payload.campaign.ai_credits_exhausted_provider == "openai"
      end)
    end

    test "broadcasts to user channel", %{campaign: campaign, user: user} do
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "user:#{user.id}")

      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, :handled} =
                 AiCreditNotificationService.handle_credit_exhaustion(
                   campaign.id,
                   user.id,
                   "grok"
                 )

        assert_receive {:user_broadcast, payload}
        assert payload.campaign.is_ai_credits_exhausted == true
      end)
    end

    test "queues email notification job", %{campaign: campaign, user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, :handled} =
                 AiCreditNotificationService.handle_credit_exhaustion(
                   campaign.id,
                   user.id,
                   "grok"
                 )

        assert_enqueued(
          worker: ShotElixir.Workers.EmailWorker,
          args: %{
            "type" => "ai_credits_exhausted",
            "user_id" => user.id,
            "campaign_id" => campaign.id,
            "provider_name" => "Grok"
          }
        )
      end)
    end

    test "uses correct provider name in email for openai", %{campaign: campaign, user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        assert {:ok, :handled} =
                 AiCreditNotificationService.handle_credit_exhaustion(
                   campaign.id,
                   user.id,
                   "openai"
                 )

        assert_enqueued(
          worker: ShotElixir.Workers.EmailWorker,
          args: %{
            "type" => "ai_credits_exhausted",
            "provider_name" => "OpenAI"
          }
        )
      end)
    end

    test "rate limits notifications within cooldown period", %{campaign: campaign, user: user} do
      Oban.Testing.with_testing_mode(:manual, fn ->
        # First notification - should queue email
        assert {:ok, :handled} =
                 AiCreditNotificationService.handle_credit_exhaustion(
                   campaign.id,
                   user.id,
                   "grok"
                 )

        # Count jobs after first call
        jobs_after_first =
          Oban.Job
          |> Ecto.Query.where(queue: "emails")
          |> Ecto.Query.where([j], j.worker == "ShotElixir.Workers.EmailWorker")
          |> Repo.all()

        assert length(jobs_after_first) == 1

        # Second notification within cooldown - should NOT queue another email
        assert {:ok, :handled} =
                 AiCreditNotificationService.handle_credit_exhaustion(
                   campaign.id,
                   user.id,
                   "grok"
                 )

        # Should still only have 1 job (cooldown prevented second email)
        jobs_after_second =
          Oban.Job
          |> Ecto.Query.where(queue: "emails")
          |> Ecto.Query.where([j], j.worker == "ShotElixir.Workers.EmailWorker")
          |> Repo.all()

        assert length(jobs_after_second) == 1
      end)
    end
  end

  describe "credits_exhausted?/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-exhausted-check@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Exhausted Check Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "returns false when credits not exhausted", %{campaign: campaign} do
      refute AiCreditNotificationService.credits_exhausted?(campaign.id)
    end

    test "returns true when credits exhausted within 24 hours", %{campaign: campaign} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      campaign
      |> Ecto.Changeset.change(%{
        ai_credits_exhausted_at: now,
        ai_credits_exhausted_provider: "grok"
      })
      |> Repo.update!()

      assert AiCreditNotificationService.credits_exhausted?(campaign.id)
    end

    test "returns false when credits exhausted more than 24 hours ago", %{campaign: campaign} do
      old_time =
        DateTime.utc_now()
        |> DateTime.add(-25, :hour)
        |> DateTime.truncate(:second)

      campaign
      |> Ecto.Changeset.change(%{
        ai_credits_exhausted_at: old_time,
        ai_credits_exhausted_provider: "grok"
      })
      |> Repo.update!()

      refute AiCreditNotificationService.credits_exhausted?(campaign.id)
    end

    test "returns false when campaign not found" do
      fake_id = Ecto.UUID.generate()
      refute AiCreditNotificationService.credits_exhausted?(fake_id)
    end
  end

  describe "exhausted_provider/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-provider-check@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Provider Check Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign}
    end

    test "returns nil when credits not exhausted", %{campaign: campaign} do
      assert AiCreditNotificationService.exhausted_provider(campaign.id) == nil
    end

    test "returns provider when credits exhausted", %{campaign: campaign} do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      campaign
      |> Ecto.Changeset.change(%{
        ai_credits_exhausted_at: now,
        ai_credits_exhausted_provider: "openai"
      })
      |> Repo.update!()

      assert AiCreditNotificationService.exhausted_provider(campaign.id) == "openai"
    end

    test "returns nil when exhaustion expired", %{campaign: campaign} do
      old_time =
        DateTime.utc_now()
        |> DateTime.add(-25, :hour)
        |> DateTime.truncate(:second)

      campaign
      |> Ecto.Changeset.change(%{
        ai_credits_exhausted_at: old_time,
        ai_credits_exhausted_provider: "gemini"
      })
      |> Repo.update!()

      assert AiCreditNotificationService.exhausted_provider(campaign.id) == nil
    end

    test "returns nil when campaign not found" do
      fake_id = Ecto.UUID.generate()
      assert AiCreditNotificationService.exhausted_provider(fake_id) == nil
    end
  end
end
