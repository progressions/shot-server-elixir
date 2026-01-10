defmodule ShotElixir.MediaTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Media
  alias ShotElixir.{Accounts, Campaigns}

  setup do
    {:ok, user} =
      Accounts.create_user(%{
        email: "test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User",
        gamemaster: true
      })

    {:ok, campaign} =
      Campaigns.create_campaign(%{
        name: "Test Campaign",
        description: "Test campaign",
        user_id: user.id
      })

    {:ok, user: user, campaign: campaign}
  end

  describe "list_campaign_images/2 sorting" do
    setup %{campaign: campaign, user: user} do
      # Create test images with different attributes
      {:ok, image1} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "orphan",
          imagekit_file_id: "test_1",
          imagekit_url: "https://example.com/image1.jpg",
          filename: "alpha.jpg",
          byte_size: 1000,
          entity_type: "Character",
          uploaded_by_id: user.id
        })

      # Sleep to ensure different timestamps (PostgreSQL timestamp precision requires ~100ms gap)
      Process.sleep(100)

      {:ok, image2} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "ai_generated",
          status: "attached",
          imagekit_file_id: "test_2",
          imagekit_url: "https://example.com/image2.jpg",
          filename: "beta.jpg",
          byte_size: 5000,
          entity_type: "Vehicle",
          generated_by_id: user.id
        })

      Process.sleep(100)

      {:ok, image3} =
        Media.create_image(%{
          campaign_id: campaign.id,
          source: "upload",
          status: "orphan",
          imagekit_file_id: "test_3",
          imagekit_url: "https://example.com/image3.jpg",
          filename: "charlie.jpg",
          byte_size: 2500,
          entity_type: "Character",
          uploaded_by_id: user.id
        })

      {:ok, image1: image1, image2: image2, image3: image3}
    end

    test "sorts by inserted_at descending by default", %{campaign: campaign} do
      result = Media.list_campaign_images(campaign.id, %{})

      # Verify all 3 images returned in descending order (newest first)
      assert length(result.images) == 3
      [first, second, third] = result.images
      assert DateTime.compare(first.inserted_at, second.inserted_at) in [:gt, :eq]
      assert DateTime.compare(second.inserted_at, third.inserted_at) in [:gt, :eq]
    end

    test "sorts by inserted_at ascending", %{campaign: campaign} do
      result =
        Media.list_campaign_images(campaign.id, %{"sort" => "inserted_at", "order" => "asc"})

      # Verify all 3 images returned in ascending order (oldest first)
      assert length(result.images) == 3
      [first, second, third] = result.images
      assert DateTime.compare(first.inserted_at, second.inserted_at) in [:lt, :eq]
      assert DateTime.compare(second.inserted_at, third.inserted_at) in [:lt, :eq]
    end

    test "sorts by filename ascending", %{campaign: campaign, image1: image1} do
      result = Media.list_campaign_images(campaign.id, %{"sort" => "filename", "order" => "asc"})

      # "alpha.jpg" should be first
      assert hd(result.images).id == image1.id
    end

    test "sorts by filename descending", %{campaign: campaign, image3: image3} do
      result = Media.list_campaign_images(campaign.id, %{"sort" => "filename", "order" => "desc"})

      # "charlie.jpg" should be first
      assert hd(result.images).id == image3.id
    end

    test "sorts by byte_size ascending", %{campaign: campaign, image1: image1} do
      result = Media.list_campaign_images(campaign.id, %{"sort" => "byte_size", "order" => "asc"})

      # Smallest (1000 bytes) should be first
      assert hd(result.images).id == image1.id
    end

    test "sorts by byte_size descending", %{campaign: campaign, image2: image2} do
      result =
        Media.list_campaign_images(campaign.id, %{"sort" => "byte_size", "order" => "desc"})

      # Largest (5000 bytes) should be first
      assert hd(result.images).id == image2.id
    end

    test "sorts by entity_type ascending", %{campaign: campaign} do
      result =
        Media.list_campaign_images(campaign.id, %{"sort" => "entity_type", "order" => "asc"})

      # "Character" should come before "Vehicle"
      first_type = hd(result.images).entity_type
      assert first_type == "Character"
    end

    test "sorts by entity_type descending", %{campaign: campaign} do
      result =
        Media.list_campaign_images(campaign.id, %{"sort" => "entity_type", "order" => "desc"})

      # "Vehicle" should come first
      first_type = hd(result.images).entity_type
      assert first_type == "Vehicle"
    end

    test "falls back to inserted_at for invalid sort field", %{campaign: campaign} do
      result =
        Media.list_campaign_images(campaign.id, %{"sort" => "invalid_field", "order" => "desc"})

      # Should use default (inserted_at desc), so verify descending order
      assert length(result.images) == 3
      [first, second, third] = result.images
      assert DateTime.compare(first.inserted_at, second.inserted_at) in [:gt, :eq]
      assert DateTime.compare(second.inserted_at, third.inserted_at) in [:gt, :eq]
    end

    test "defaults to descending order when order is invalid", %{campaign: campaign} do
      result =
        Media.list_campaign_images(campaign.id, %{"sort" => "inserted_at", "order" => "invalid"})

      # Should use default desc order
      assert length(result.images) == 3
      [first, second, third] = result.images
      assert DateTime.compare(first.inserted_at, second.inserted_at) in [:gt, :eq]
      assert DateTime.compare(second.inserted_at, third.inserted_at) in [:gt, :eq]
    end
  end
end
