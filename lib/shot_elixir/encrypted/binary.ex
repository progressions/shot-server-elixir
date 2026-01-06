defmodule ShotElixir.Encrypted.Binary do
  @moduledoc """
  Custom Ecto type for encrypted binary fields.
  Uses Phoenix's built-in MessageEncryptor (AES-GCM under the hood).

  Keys are derived from SECRET_KEY_BASE, so no additional configuration needed.

  ## Key Rotation Warning

  Encryption keys are derived from the application's SECRET_KEY_BASE using static
  salts ("encrypted binary secret" and "encrypted binary sign"). While MessageEncryptor
  uses unique initialization vectors per encryption (so identical plaintexts produce
  different ciphertexts), the derived keys remain constant for a given SECRET_KEY_BASE.

  **Important:** If SECRET_KEY_BASE is rotated, all existing encrypted credentials
  will become unreadable and users will need to re-enter their API keys/tokens.

  To rotate keys while preserving data:
  1. Export all credentials (decrypted) before rotation
  2. Rotate SECRET_KEY_BASE
  3. Re-encrypt and store all credentials with new keys

  Alternatively, implement a key versioning scheme that stores the key version
  with each encrypted value and supports decryption with multiple key versions.
  """
  use Ecto.Type

  @impl true
  def type, do: :binary

  @impl true
  def cast(nil), do: {:ok, nil}
  def cast(value) when is_binary(value), do: {:ok, value}
  def cast(_), do: :error

  @impl true
  def dump(nil), do: {:ok, nil}

  def dump(value) when is_binary(value) do
    encrypted = Plug.Crypto.MessageEncryptor.encrypt(value, secret(), sign_secret())
    {:ok, encrypted}
  end

  def dump(_), do: :error

  @impl true
  def load(nil), do: {:ok, nil}

  def load(encrypted) when is_binary(encrypted) do
    case Plug.Crypto.MessageEncryptor.decrypt(encrypted, secret(), sign_secret()) do
      {:ok, value} -> {:ok, value}
      :error -> :error
    end
  end

  def load(_), do: :error

  # Derive encryption key from SECRET_KEY_BASE
  defp secret do
    base = secret_key_base()
    Plug.Crypto.KeyGenerator.generate(base, "encrypted binary secret", length: 32)
  end

  # Derive signing key from SECRET_KEY_BASE
  defp sign_secret do
    base = secret_key_base()
    Plug.Crypto.KeyGenerator.generate(base, "encrypted binary sign", length: 32)
  end

  defp secret_key_base do
    case Application.get_env(:shot_elixir, ShotElixirWeb.Endpoint) do
      nil ->
        raise """
        :secret_key_base is not configured for ShotElixirWeb.Endpoint.

        ShotElixir.Encrypted.Binary derives encryption keys from your endpoint's
        :secret_key_base. Please ensure it is set in your config (e.g. config/runtime.exs)
        for the :shot_elixir, ShotElixirWeb.Endpoint application.
        """

      config ->
        case config[:secret_key_base] do
          nil ->
            raise """
            :secret_key_base is nil for ShotElixirWeb.Endpoint.

            ShotElixir.Encrypted.Binary requires a non-empty :secret_key_base
            to derive encryption keys. Please check your endpoint configuration.
            """

          "" ->
            raise """
            :secret_key_base is empty for ShotElixirWeb.Endpoint.

            ShotElixir.Encrypted.Binary requires a non-empty :secret_key_base
            to derive encryption keys. Please check your endpoint configuration.
            """

          key when is_binary(key) ->
            key
        end
    end
  end
end
