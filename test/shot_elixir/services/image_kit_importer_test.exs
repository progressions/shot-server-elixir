defmodule ShotElixir.Services.ImageKitImporterTest do
  use ShotElixir.DataCase

  alias ShotElixir.Services.ImageKitImporter
  alias ShotElixir.Accounts
  alias ShotElixir.Campaigns.Campaign
  alias ShotElixir.Characters.Character
  alias ShotElixir.Weapons.Weapon

  describe "call/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-importer@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Test Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Test Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign, character: character}
    end

    test "returns error for invalid URL", %{character: character} do
      result =
        ImageKitImporter.call(
          source_url: "http://invalid-domain-that-does-not-exist.fake/image.jpg",
          attachable_type: "Character",
          attachable_id: character.id
        )

      assert {:error, _reason} = result
    end

    test "returns error for empty URL", %{character: character} do
      assert_raise KeyError, fn ->
        ImageKitImporter.call(
          attachable_type: "Character",
          attachable_id: character.id
        )
      end
    end

    test "validates required options" do
      assert_raise KeyError, fn ->
        ImageKitImporter.call(source_url: "http://example.com/image.jpg")
      end
    end
  end

  describe "import_for/1" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-import-for@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Import For Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, character} =
        %Character{}
        |> Character.changeset(%{
          name: "Import For Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, weapon} =
        %Weapon{}
        |> Weapon.changeset(%{
          name: "Import For Weapon",
          campaign_id: campaign.id,
          damage: 10,
          active: true
        })
        |> Repo.insert()

      {:ok, user: user, campaign: campaign, character: character, weapon: weapon}
    end

    test "extracts entity info from Character struct", %{character: character} do
      result =
        ImageKitImporter.import_for(
          source_url: "http://invalid-domain.fake/image.jpg",
          entity: character
        )

      # Will fail on network request but should parse entity correctly
      assert {:error, _reason} = result
    end

    test "extracts entity info from Weapon struct", %{weapon: weapon} do
      result =
        ImageKitImporter.import_for(
          source_url: "http://invalid-domain.fake/image.jpg",
          entity: weapon
        )

      assert {:error, _reason} = result
    end

    test "requires source_url option" do
      assert_raise KeyError, fn ->
        ImageKitImporter.import_for(entity: %{id: "test"})
      end
    end

    test "requires entity option" do
      assert_raise KeyError, fn ->
        ImageKitImporter.import_for(source_url: "http://example.com/image.jpg")
      end
    end
  end

  describe "copy_image/2" do
    setup do
      {:ok, user} =
        Accounts.create_user(%{
          email: "gm-copy@example.com",
          password: "password123",
          first_name: "Game",
          last_name: "Master",
          gamemaster: true
        })

      {:ok, campaign} =
        %Campaign{}
        |> Campaign.changeset(%{
          name: "Copy Image Campaign",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, source_character} =
        %Character{}
        |> Character.changeset(%{
          name: "Source Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok, target_character} =
        %Character{}
        |> Character.changeset(%{
          name: "Target Character",
          campaign_id: campaign.id,
          user_id: user.id,
          active: true
        })
        |> Repo.insert()

      {:ok,
       user: user,
       campaign: campaign,
       source_character: source_character,
       target_character: target_character}
    end

    test "returns :no_image when source has no image attached", %{
      source_character: source,
      target_character: target
    } do
      result = ImageKitImporter.copy_image(source, target)
      assert {:error, :no_image} = result
    end
  end
end
