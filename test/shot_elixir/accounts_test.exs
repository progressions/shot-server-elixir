defmodule ShotElixir.AccountsTest do
  use ShotElixir.DataCase, async: true

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

    test "create_user/1 validates password strength" do
      # Too short
      attrs = Map.put(@valid_attrs, :password, "short1")
      assert {:error, %Ecto.Changeset{} = changeset} = Accounts.create_user(attrs)
      assert "must be at least 8 characters" in changeset_errors(changeset).password

      # No numbers
      attrs2 = Map.put(@valid_attrs, :password, "longpassword")
      assert {:error, %Ecto.Changeset{} = changeset2} = Accounts.create_user(attrs2)
      assert "must contain at least one number" in changeset_errors(changeset2).password

      # No letters
      attrs3 = Map.put(@valid_attrs, :password, "12345678")
      assert {:error, %Ecto.Changeset{} = changeset3} = Accounts.create_user(attrs3)
      assert "must contain at least one letter" in changeset_errors(changeset3).password
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
      assert_receive {:campaign_broadcast, %{"user" => broadcast_user}}, 1000
      assert_receive {:campaign_broadcast, %{"user" => broadcast_user2}}, 1000

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

  describe "Discord account linking" do
    test "link_discord/2 links Discord ID to user" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      discord_id = 123_456_789_012_345_678

      assert {:ok, updated_user} = Accounts.link_discord(user, discord_id)
      assert updated_user.discord_id == discord_id
    end

    test "link_discord/2 enforces unique constraint" do
      discord_id = 123_456_789_012_345_679

      {:ok, user1} = Accounts.create_user(@valid_attrs)
      {:ok, _} = Accounts.link_discord(user1, discord_id)

      {:ok, user2} =
        Accounts.create_user(%{
          email: "user2@example.com",
          password: "password123",
          first_name: "User",
          last_name: "Two"
        })

      assert {:error, changeset} = Accounts.link_discord(user2, discord_id)
      assert "has already been taken" in changeset_errors(changeset).discord_id
    end

    test "unlink_discord/1 removes Discord ID from user" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      discord_id = 123_456_789_012_345_680

      {:ok, linked_user} = Accounts.link_discord(user, discord_id)
      assert linked_user.discord_id == discord_id

      {:ok, unlinked_user} = Accounts.unlink_discord(linked_user)
      assert unlinked_user.discord_id == nil
    end

    test "get_user_by_discord_id/1 finds user by Discord ID" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      discord_id = 123_456_789_012_345_681

      {:ok, _} = Accounts.link_discord(user, discord_id)

      found_user = Accounts.get_user_by_discord_id(discord_id)
      assert found_user.id == user.id
    end

    test "get_user_by_discord_id/1 returns nil for non-existent Discord ID" do
      assert nil == Accounts.get_user_by_discord_id(999_999_999_999_999_999)
    end
  end

  describe "change_password/3" do
    test "successfully changes password with valid current password" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:ok, updated_user} =
               Accounts.change_password(user, "password123", "newpassword1")

      # Verify the new password works for authentication
      assert {:ok, _} = Accounts.authenticate_user(user.email, "newpassword1")

      # Verify the old password no longer works
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_user(user.email, "password123")
    end

    test "fails when current password is incorrect" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:error, :invalid_current_password} =
               Accounts.change_password(user, "wrongpassword", "newpassword1")

      # Verify the original password still works
      assert {:ok, _} = Accounts.authenticate_user(user.email, "password123")
    end

    test "fails when new password is too short" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:error, changeset} =
               Accounts.change_password(user, "password123", "short1")

      assert "must be at least 8 characters" in changeset_errors(changeset).password
    end

    test "fails when new password has no numbers" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:error, changeset} =
               Accounts.change_password(user, "password123", "longpassword")

      assert "must contain at least one number" in changeset_errors(changeset).password
    end

    test "fails when new password has no letters" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:error, changeset} =
               Accounts.change_password(user, "password123", "12345678")

      assert "must contain at least one letter" in changeset_errors(changeset).password
    end
  end

  describe "OTP passwordless login" do
    test "generate_otp_code/1 generates a 6-digit code and magic token" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      {:ok, updated_user, otp_code, magic_token} = Accounts.generate_otp_code(user)

      # OTP code should be 6 digits
      assert String.length(otp_code) == 6
      assert String.match?(otp_code, ~r/^\d{6}$/)

      # Magic token should be a base64 encoded string
      assert is_binary(magic_token)
      assert String.length(magic_token) > 0

      # User should have token data stored
      assert updated_user.reset_password_token != nil
      assert updated_user.reset_password_sent_at != nil

      # Token should contain both OTP and magic token
      assert String.contains?(updated_user.reset_password_token, "|")
    end

    test "generate_otp_code/1 generates cryptographically secure codes" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      # Generate multiple codes and verify they're different (statistically)
      codes =
        for _ <- 1..10 do
          {:ok, _user, otp_code, _magic_token} = Accounts.generate_otp_code(user)
          otp_code
        end

      unique_codes = Enum.uniq(codes)
      # With 10 codes, we should have at least 5 unique ones (extremely likely with CSPRNG)
      assert length(unique_codes) >= 5
    end

    test "verify_otp_code/2 with valid code returns user" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      {:ok, _updated_user, otp_code, _magic_token} = Accounts.generate_otp_code(user)

      assert {:ok, verified_user} = Accounts.verify_otp_code(user.email, otp_code)
      assert verified_user.id == user.id
    end

    test "verify_otp_code/2 with invalid code returns error" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      {:ok, _updated_user, _otp_code, _magic_token} = Accounts.generate_otp_code(user)

      assert {:error, :invalid_code} = Accounts.verify_otp_code(user.email, "000000")
    end

    test "verify_otp_code/2 with non-existent email returns error" do
      assert {:error, :invalid_code} =
               Accounts.verify_otp_code("nonexistent@example.com", "123456")
    end

    test "verify_otp_code/2 with expired code returns error" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      {:ok, updated_user, otp_code, _magic_token} = Accounts.generate_otp_code(user)

      # Set sent_at to be expired (more than 10 minutes ago)
      expired_time = NaiveDateTime.add(NaiveDateTime.utc_now(), -11 * 60, :second)

      updated_user
      |> Ecto.Changeset.change(reset_password_sent_at: expired_time)
      |> ShotElixir.Repo.update!()

      assert {:error, :expired} = Accounts.verify_otp_code(user.email, otp_code)
    end

    test "verify_otp_code/2 with no OTP set returns error" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:error, :invalid_code} = Accounts.verify_otp_code(user.email, "123456")
    end

    test "verify_magic_token/1 with valid token returns user" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      {:ok, _updated_user, _otp_code, magic_token} = Accounts.generate_otp_code(user)

      assert {:ok, verified_user} = Accounts.verify_magic_token(magic_token)
      assert verified_user.id == user.id
    end

    test "verify_magic_token/1 with invalid token returns error" do
      assert {:error, :invalid_token} = Accounts.verify_magic_token("invalid_token")
    end

    test "verify_magic_token/1 with expired token returns error" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      {:ok, updated_user, _otp_code, magic_token} = Accounts.generate_otp_code(user)

      # Set sent_at to be expired
      expired_time = NaiveDateTime.add(NaiveDateTime.utc_now(), -11 * 60, :second)

      updated_user
      |> Ecto.Changeset.change(reset_password_sent_at: expired_time)
      |> ShotElixir.Repo.update!()

      assert {:error, :expired} = Accounts.verify_magic_token(magic_token)
    end

    test "clear_otp_code/1 clears the OTP data" do
      {:ok, user} = Accounts.create_user(@valid_attrs)
      {:ok, updated_user, _otp_code, _magic_token} = Accounts.generate_otp_code(user)

      # Verify OTP data exists
      assert updated_user.reset_password_token != nil
      assert updated_user.reset_password_sent_at != nil

      # Clear the OTP
      {:ok, cleared_user} = Accounts.clear_otp_code(updated_user)

      assert cleared_user.reset_password_token == nil
      assert cleared_user.reset_password_sent_at == nil
    end
  end

  describe "current character functions" do
    alias ShotElixir.Campaigns
    alias ShotElixir.Characters

    setup do
      # Create a user with discord linked
      {:ok, user} = Accounts.create_user(@valid_attrs)
      discord_id = 123_456_789_012_345_700
      {:ok, user} = Accounts.link_discord(user, discord_id)

      # Create a campaign owned by the user
      {:ok, campaign} =
        Campaigns.create_campaign(%{
          name: "Test Campaign",
          user_id: user.id,
          active: true
        })

      # Create a character owned by the user
      {:ok, character} =
        Characters.create_character(%{
          "name" => "Test Character",
          "user_id" => user.id,
          "campaign_id" => campaign.id,
          "active" => true,
          "action_values" => %{"Type" => "PC"}
        })

      # Create another user and character (for ownership tests)
      {:ok, other_user} =
        Accounts.create_user(%{
          email: "other@example.com",
          password: "password123",
          first_name: "Other",
          last_name: "User"
        })

      {:ok, other_character} =
        Characters.create_character(%{
          "name" => "Other Character",
          "user_id" => other_user.id,
          "campaign_id" => campaign.id,
          "active" => true,
          "action_values" => %{"Type" => "PC"}
        })

      %{
        user: user,
        discord_id: discord_id,
        campaign: campaign,
        character: character,
        other_user: other_user,
        other_character: other_character
      }
    end

    test "set_current_character/2 sets a valid character for user", %{
      user: user,
      character: character
    } do
      assert {:ok, updated_user} = Accounts.set_current_character(user, character.id)
      assert updated_user.current_character_id == character.id
    end

    test "set_current_character/2 clears character when nil is passed", %{
      user: user,
      character: character
    } do
      # First set a character
      {:ok, user_with_char} = Accounts.set_current_character(user, character.id)
      assert user_with_char.current_character_id == character.id

      # Then clear it
      assert {:ok, cleared_user} = Accounts.set_current_character(user_with_char, nil)
      assert cleared_user.current_character_id == nil
    end

    test "set_current_character/2 fails when character belongs to another user", %{
      user: user,
      other_character: other_character
    } do
      assert {:error, changeset} = Accounts.set_current_character(user, other_character.id)

      assert "does not belong to this user or does not exist" in changeset_errors(changeset).current_character_id
    end

    test "set_current_character/2 fails when character does not exist", %{user: user} do
      fake_id = Ecto.UUID.generate()
      assert {:error, changeset} = Accounts.set_current_character(user, fake_id)

      assert "does not belong to this user or does not exist" in changeset_errors(changeset).current_character_id
    end

    test "get_user_with_current_character/1 returns user with preloaded associations", %{
      user: user,
      discord_id: discord_id,
      character: character
    } do
      # Set a current character first
      {:ok, _} = Accounts.set_current_character(user, character.id)

      # Fetch user with preloaded associations
      fetched_user = Accounts.get_user_with_current_character(discord_id)

      assert fetched_user.id == user.id
      assert fetched_user.current_character.id == character.id
      assert Ecto.assoc_loaded?(fetched_user.current_campaign)
      assert Ecto.assoc_loaded?(fetched_user.characters)
    end

    test "get_user_with_current_character/1 returns nil for non-existent Discord ID" do
      assert nil == Accounts.get_user_with_current_character(999_999_999_999_999_999)
    end

    test "get_user_with_current_character/1 returns nil for invalid input" do
      assert nil == Accounts.get_user_with_current_character(nil)
      assert nil == Accounts.get_user_with_current_character("not_an_integer")
    end
  end

  describe "cli_authorization_codes" do
    @valid_user_attrs %{
      email: "cli-auth-context-test@example.com",
      password: "password123",
      first_name: "CLI",
      last_name: "User"
    }

    test "create_cli_auth_code/0 creates a code with expiry" do
      assert {:ok, auth_code} = Accounts.create_cli_auth_code()

      assert auth_code.code
      assert String.length(auth_code.code) == 32
      assert auth_code.approved == false
      assert auth_code.user_id == nil
      assert auth_code.expires_at

      # Should expire in the future (approximately 10 minutes)
      expires_in = DateTime.diff(auth_code.expires_at, DateTime.utc_now())
      assert expires_in > 590 and expires_in <= 600
    end

    test "create_cli_auth_code/0 generates unique codes" do
      {:ok, code1} = Accounts.create_cli_auth_code()
      {:ok, code2} = Accounts.create_cli_auth_code()

      refute code1.code == code2.code
    end

    test "get_cli_auth_code/1 returns code when valid and not expired" do
      {:ok, auth_code} = Accounts.create_cli_auth_code()

      fetched = Accounts.get_cli_auth_code(auth_code.code)

      assert fetched.id == auth_code.id
      assert fetched.code == auth_code.code
    end

    test "get_cli_auth_code/1 returns nil for non-existent code" do
      assert nil == Accounts.get_cli_auth_code("nonexistent")
    end

    test "get_cli_auth_code/1 returns nil for invalid input" do
      assert nil == Accounts.get_cli_auth_code(nil)
      assert nil == Accounts.get_cli_auth_code(123)
    end

    test "approve_cli_auth_code/2 approves a valid code" do
      {:ok, auth_code} = Accounts.create_cli_auth_code()
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      assert {:ok, approved} = Accounts.approve_cli_auth_code(auth_code.code, user)

      assert approved.approved == true
      assert approved.user_id == user.id
    end

    test "approve_cli_auth_code/2 returns error for non-existent code" do
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      assert {:error, :not_found} = Accounts.approve_cli_auth_code("nonexistent", user)
    end

    test "approve_cli_auth_code/2 returns error when already approved" do
      {:ok, auth_code} = Accounts.create_cli_auth_code()
      {:ok, user} = Accounts.create_user(@valid_user_attrs)

      # First approval
      {:ok, _} = Accounts.approve_cli_auth_code(auth_code.code, user)

      # Second approval attempt
      assert {:error, :already_approved} = Accounts.approve_cli_auth_code(auth_code.code, user)
    end

    test "poll_cli_auth_code/1 returns pending for unapproved code" do
      {:ok, auth_code} = Accounts.create_cli_auth_code()

      assert {:pending, expires_in} = Accounts.poll_cli_auth_code(auth_code.code)

      assert expires_in > 0
    end

    test "poll_cli_auth_code/1 returns approved with user for approved code" do
      {:ok, auth_code} = Accounts.create_cli_auth_code()
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      {:ok, _} = Accounts.approve_cli_auth_code(auth_code.code, user)

      assert {:approved, returned_user} = Accounts.poll_cli_auth_code(auth_code.code)

      assert returned_user.id == user.id
      assert returned_user.email == user.email
    end

    test "poll_cli_auth_code/1 returns expired for non-existent code" do
      assert {:error, :expired} = Accounts.poll_cli_auth_code("nonexistent")
    end

    test "poll_cli_auth_code/1 returns expired for invalid input" do
      assert {:error, :expired} = Accounts.poll_cli_auth_code(nil)
    end

    test "poll_cli_auth_code/1 returns expired when user no longer exists" do
      {:ok, auth_code} = Accounts.create_cli_auth_code()
      {:ok, user} = Accounts.create_user(@valid_user_attrs)
      {:ok, _} = Accounts.approve_cli_auth_code(auth_code.code, user)

      # Delete the user
      ShotElixir.Repo.delete!(user)

      # Should return expired since user no longer exists
      assert {:error, :expired} = Accounts.poll_cli_auth_code(auth_code.code)
    end
  end
end
