defmodule ShotElixir.AccountsTest do
  use ShotElixir.DataCase

  alias ShotElixir.Accounts
  alias ShotElixir.Accounts.User

  describe "users" do
    @valid_attrs %{
      email: "test@example.com",
      password: "password123",
      first_name: "John",
      last_name: "Doe",
      admin: false,
      gamemaster: true
    }

    @update_attrs %{
      first_name: "Jane",
      last_name: "Smith",
      gamemaster: false
    }

    @invalid_attrs %{
      email: nil,
      first_name: nil,
      last_name: nil
    }

    test "list_users/0 returns all users" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      users = Accounts.list_users()
      assert Enum.any?(users, fn u -> u.id == user.id end)
    end

    test "get_user!/1 returns the user with given id" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      fetched = Accounts.get_user!(user.id)
      assert fetched.id == user.id
    end

    test "get_user/1 returns the user with given id" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      fetched = Accounts.get_user(user.id)
      assert fetched.id == user.id
    end

    test "get_user/1 returns nil for invalid id" do
      assert Accounts.get_user(Ecto.UUID.generate()) == nil
    end

    test "create_user/1 with valid data creates a user" do
      assert {:ok, %User{} = user} = Accounts.create_user(@valid_attrs)
      assert user.email == "test@example.com"
      assert user.first_name == "John"
      assert user.last_name == "Doe"
      assert user.name == "John Doe"
      assert user.encrypted_password
      assert user.jti
    end

    test "create_user/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Accounts.create_user(@invalid_attrs)
    end

    test "create_user/1 with duplicate email returns error" do
      {:ok, _} = Accounts.create_user(@valid_attrs)
      assert {:error, %Ecto.Changeset{} = changeset} = Accounts.create_user(@valid_attrs)
      assert "has already been taken" in changeset_errors(changeset).email
    end

    test "create_user/1 validates email format" do
      attrs = Map.put(@valid_attrs, :email, "invalid-email")
      assert {:error, %Ecto.Changeset{} = changeset} = Accounts.create_user(attrs)
      assert "has invalid format" in changeset_errors(changeset).email
    end

    test "create_user/1 validates minimum password length" do
      attrs = Map.put(@valid_attrs, :password, "short")
      assert {:error, %Ecto.Changeset{} = changeset} = Accounts.create_user(attrs)
      assert "should be at least 6 characters" in changeset_errors(changeset).password
    end

    test "update_user/2 with valid data updates the user" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert {:ok, updated} = Accounts.update_user(user, @update_attrs)
      assert updated.first_name == "Jane"
      assert updated.last_name == "Smith"
      assert updated.gamemaster == false
    end

    test "update_user/2 with invalid data returns error changeset" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert {:error, %Ecto.Changeset{}} = Accounts.update_user(user, @invalid_attrs)
      fetched = Accounts.get_user!(user.id)
      assert fetched.first_name == user.first_name
    end

    test "delete_user/1 soft deletes the user" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert {:ok, deleted} = Accounts.delete_user(user)
      assert deleted.active == false
    end

    test "authenticate_user/2 with valid credentials" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:ok, authenticated_user} =
               Accounts.authenticate_user("test@example.com", "password123")

      assert authenticated_user.id == user.id
    end

    test "authenticate_user/2 with invalid password" do
      {:ok, _user} = Accounts.create_user(@valid_attrs)

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("test@example.com", "wrongpassword")
    end

    test "authenticate_user/2 with non-existent user" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user("nonexistent@example.com", "password123")
    end

    test "get_user_by_email/1 finds user by email" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      found_user = Accounts.get_user_by_email("test@example.com")
      assert found_user.id == user.id
    end

    test "get_user_by_email/1 returns nil for non-existent email" do
      assert nil == Accounts.get_user_by_email("nonexistent@example.com")
    end

    test "generate_auth_token/1 returns a JWT token" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      assert {:ok, token, _claims} = Accounts.generate_auth_token(user)
      assert is_binary(token)
    end

    test "validate_token/1 with valid token returns user" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      {:ok, token, _} = Accounts.generate_auth_token(user)

      assert {:ok, validated_user} = Accounts.validate_token(token)
      assert validated_user.id == user.id
    end

    test "validate_token/1 with invalid token returns error" do
      assert {:error, _} = Accounts.validate_token("invalid_token")
    end

    test "update_user/2 broadcasts to all associated campaigns" do
      # Create user and campaigns
      {:ok, user} = Accounts.create_user(@valid_attrs)

      # Create a second user to own the member campaign
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User",
          gamemaster: true
        })

      # Create campaigns - one owned by user, one where user is a member
      {:ok, owned_campaign} =
        ShotElixir.Campaigns.create_campaign(%{
          name: "Owned Campaign",
          user_id: user.id,
          description: "Campaign owned by user"
        })

      {:ok, member_campaign} =
        ShotElixir.Campaigns.create_campaign(%{
          name: "Member Campaign",
          user_id: other_user.id,
          description: "Campaign where user is member"
        })

      # Add user as member to the second campaign
      ShotElixir.Campaigns.add_member(member_campaign, user)

      # Create image position for the user
      {:ok, _image_position} =
        ShotElixir.Repo.insert(%ShotElixir.ImagePositions.ImagePosition{
          positionable_type: "User",
          positionable_id: user.id,
          context: "profile",
          x_position: 50.0,
          y_position: 50.0
        })

      # Subscribe to both campaign channels
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{owned_campaign.id}")
      Phoenix.PubSub.subscribe(ShotElixir.PubSub, "campaign:#{member_campaign.id}")

      # Update the user
      {:ok, updated_user} = Accounts.update_user(user, %{first_name: "UpdatedName"})

      # Assert broadcasts were received for both campaigns
      assert_receive {:rails_message, %{"user" => broadcast_user}}, 1000
      assert_receive {:rails_message, %{"user" => broadcast_user2}}, 1000

      # Verify broadcast includes updated user data
      # The view renders with atom keys, not string keys
      assert broadcast_user[:first_name] == "UpdatedName"
      assert broadcast_user[:id] == updated_user.id

      # Verify image_positions are included in broadcast
      assert is_list(broadcast_user[:image_positions])
      assert length(broadcast_user[:image_positions]) == 1

      image_pos = List.first(broadcast_user[:image_positions])
      assert image_pos[:context] == "profile"
      assert image_pos[:x_position] == 50.0
      assert image_pos[:y_position] == 50.0

      # Verify second broadcast has same data
      assert broadcast_user2[:first_name] == "UpdatedName"
      assert broadcast_user2[:id] == updated_user.id
      assert is_list(broadcast_user2[:image_positions])
    end
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
