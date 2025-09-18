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
  end

  defp changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
