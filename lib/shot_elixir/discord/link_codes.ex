defmodule ShotElixir.Discord.LinkCodes do
  @moduledoc """
  Agent that stores temporary link codes for Discord account linking.
  Maps code -> %{discord_id: id, discord_username: username, expires_at: DateTime}

  Codes expire after 5 minutes.
  """
  use Agent

  @code_expiry_minutes 5
  @code_length 6
  @code_chars ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  def start_link(_opts) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Generates a unique link code for a Discord user.
  Returns the code string.
  Uses atomic get_and_update to prevent race conditions in code generation.
  """
  def generate(discord_id, discord_username) when is_integer(discord_id) do
    expires_at = DateTime.add(DateTime.utc_now(), @code_expiry_minutes * 60, :second)

    Agent.get_and_update(__MODULE__, fn state ->
      # Remove any existing codes for this Discord user
      state = remove_codes_for_discord_id(state, discord_id)

      # Generate a unique code atomically within the same operation
      code = generate_unique_code_atomic(state)

      # Add the new code
      new_state =
        Map.put(state, code, %{
          discord_id: discord_id,
          discord_username: discord_username,
          expires_at: expires_at
        })

      {code, new_state}
    end)
  end

  @doc """
  Validates a link code and returns the Discord user info if valid.
  Returns {:ok, %{discord_id: id, discord_username: username}} or {:error, reason}.
  Does NOT consume the code - use validate_and_consume/1 for atomic validation and consumption.
  """
  def validate(code) when is_binary(code) do
    code = String.upcase(code)

    Agent.get(__MODULE__, fn state ->
      case Map.get(state, code) do
        nil ->
          {:error, :invalid_code}

        %{expires_at: expires_at} = data ->
          if DateTime.compare(DateTime.utc_now(), expires_at) == :gt do
            {:error, :expired}
          else
            {:ok, data}
          end
      end
    end)
  end

  @doc """
  Atomically validates and consumes a link code in a single operation.
  Returns {:ok, %{discord_id: id, discord_username: username}} or {:error, reason}.
  The code is always consumed if it exists (even if expired) to prevent enumeration attacks.
  """
  def validate_and_consume(code) when is_binary(code) do
    code = String.upcase(code)

    Agent.get_and_update(__MODULE__, fn state ->
      case Map.get(state, code) do
        nil ->
          {{:error, :invalid_code}, state}

        %{expires_at: expires_at} = data ->
          # Always remove the code (consume it) regardless of validity
          new_state = Map.delete(state, code)

          if DateTime.compare(DateTime.utc_now(), expires_at) == :gt do
            {{:error, :expired}, new_state}
          else
            {{:ok, data}, new_state}
          end
      end
    end)
  end

  @doc """
  Consumes (deletes) a link code after successful use.
  """
  def consume(code) when is_binary(code) do
    code = String.upcase(code)
    Agent.update(__MODULE__, &Map.delete(&1, code))
  end

  @doc """
  Cleans up expired codes. Called periodically or on demand.
  """
  def cleanup_expired do
    now = DateTime.utc_now()

    Agent.update(__MODULE__, fn state ->
      state
      |> Enum.reject(fn {_code, %{expires_at: expires_at}} ->
        DateTime.compare(now, expires_at) == :gt
      end)
      |> Map.new()
    end)
  end

  # Private functions

  # Generates a unique code atomically by checking against the current state
  # This is called within the Agent.get_and_update callback to prevent race conditions
  defp generate_unique_code_atomic(state) do
    code = generate_code()

    # Ensure uniqueness by checking the state passed in (not via separate Agent.get)
    if Map.has_key?(state, code) do
      generate_unique_code_atomic(state)
    else
      code
    end
  end

  defp generate_code do
    1..@code_length
    |> Enum.map(fn _ -> Enum.random(@code_chars) end)
    |> List.to_string()
  end

  defp remove_codes_for_discord_id(state, discord_id) do
    state
    |> Enum.reject(fn {_code, %{discord_id: id}} -> id == discord_id end)
    |> Map.new()
  end
end
