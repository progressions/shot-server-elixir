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

    @invalid_attrs %{
      email: nil,
      first_name: nil,
      last_name: nil
    }

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

    test "create_user/1 validates email format" do
      attrs = Map.put(@valid_attrs, :email, "invalid-email")
      assert {:error, %Ecto.Changeset{} = changeset} = Accounts.create_user(attrs)
      assert "is invalid" in changeset_errors(changeset).email
    end

    test "create_user/1 validates minimum password length" do
      attrs = Map.put(@valid_attrs, :password, "short")
      assert {:error, %Ecto.Changeset{} = changeset} = Accounts.create_user(attrs)
      assert "should be at least 6 characters" in changeset_errors(changeset).password
    end

    test "authenticate_user/2 with valid credentials" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      assert {:ok, authenticated_user} = Accounts.authenticate_user("test@example.com", "password123")
      assert authenticated_user.id == user.id
    end

    test "authenticate_user/2 with invalid password" do
      {:ok, _user} = Accounts.create_user(@valid_attrs)

      assert {:error, :invalid_credentials} = Accounts.authenticate_user("test@example.com", "wrongpassword")
    end

    test "authenticate_user/2 with non-existent user" do
      assert {:error, :invalid_credentials} = Accounts.authenticate_user("nonexistent@example.com", "password123")
    end

    test "get_user_by_email/1 finds user by email" do
      {:ok, user} = Accounts.create_user(@valid_attrs)

      found_user = Accounts.get_user_by_email("test@example.com")
      assert found_user.id == user.id
    end

    test "get_user_by_email/1 returns nil for non-existent email" do
      assert nil == Accounts.get_user_by_email("nonexistent@example.com")
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