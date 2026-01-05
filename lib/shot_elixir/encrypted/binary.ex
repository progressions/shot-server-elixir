defmodule ShotElixir.Encrypted.Binary do
  @moduledoc """
  Custom Ecto type for encrypted binary fields.
  Uses Phoenix's built-in MessageEncryptor (AES-GCM under the hood).

  Keys are derived from SECRET_KEY_BASE, so no additional configuration needed.
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
    Application.get_env(:shot_elixir, ShotElixirWeb.Endpoint)[:secret_key_base]
  end
end
