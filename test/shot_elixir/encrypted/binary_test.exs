defmodule ShotElixir.Encrypted.BinaryTest do
  use ExUnit.Case, async: true

  alias ShotElixir.Encrypted.Binary

  describe "type/0" do
    test "returns :binary" do
      assert Binary.type() == :binary
    end
  end

  describe "cast/1" do
    test "casts nil to {:ok, nil}" do
      assert Binary.cast(nil) == {:ok, nil}
    end

    test "casts binary value to {:ok, value}" do
      assert Binary.cast("test-api-key") == {:ok, "test-api-key"}
    end

    test "returns :error for non-binary values" do
      assert Binary.cast(123) == :error
      assert Binary.cast(%{}) == :error
      assert Binary.cast([]) == :error
    end
  end

  describe "dump/1" do
    test "dumps nil to {:ok, nil}" do
      assert Binary.dump(nil) == {:ok, nil}
    end

    test "encrypts binary value" do
      {:ok, encrypted} = Binary.dump("my-secret-api-key")

      # Encrypted value should be different from original
      assert encrypted != "my-secret-api-key"
      # Encrypted value should be binary
      assert is_binary(encrypted)
    end

    test "returns :error for non-binary values" do
      assert Binary.dump(123) == :error
      assert Binary.dump(%{}) == :error
    end
  end

  describe "load/1" do
    test "loads nil to {:ok, nil}" do
      assert Binary.load(nil) == {:ok, nil}
    end

    test "decrypts encrypted value" do
      original = "my-secret-api-key-12345"
      {:ok, encrypted} = Binary.dump(original)
      {:ok, decrypted} = Binary.load(encrypted)

      assert decrypted == original
    end

    test "returns :error for invalid encrypted data" do
      assert Binary.load("not-encrypted-data") == :error
    end
  end

  describe "roundtrip" do
    test "encrypts and decrypts API key correctly" do
      api_key = "xai-1234567890abcdef"

      {:ok, encrypted} = Binary.dump(api_key)
      {:ok, decrypted} = Binary.load(encrypted)

      assert decrypted == api_key
    end

    test "encrypts and decrypts OAuth token correctly" do
      oauth_token = "ya29.a0AfH6SMBx123456789-abcdefghijklmnop"

      {:ok, encrypted} = Binary.dump(oauth_token)
      {:ok, decrypted} = Binary.load(encrypted)

      assert decrypted == oauth_token
    end

    test "handles empty string" do
      {:ok, encrypted} = Binary.dump("")
      {:ok, decrypted} = Binary.load(encrypted)

      assert decrypted == ""
    end

    test "handles unicode characters" do
      value = "api-key-with-émojis-🔐"

      {:ok, encrypted} = Binary.dump(value)
      {:ok, decrypted} = Binary.load(encrypted)

      assert decrypted == value
    end

    test "produces different encrypted values for same input (due to IV)" do
      api_key = "same-api-key"

      {:ok, encrypted1} = Binary.dump(api_key)
      {:ok, encrypted2} = Binary.dump(api_key)

      # Same plaintext should produce different ciphertext (random IV)
      assert encrypted1 != encrypted2

      # But both should decrypt to the same value
      {:ok, decrypted1} = Binary.load(encrypted1)
      {:ok, decrypted2} = Binary.load(encrypted2)

      assert decrypted1 == api_key
      assert decrypted2 == api_key
    end
  end
end
