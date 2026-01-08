defmodule ShotElixir.RateLimiter do
  @moduledoc """
  Generic rate limiting using ETS with sliding window algorithm.
  Provides rate limiting for OTP requests, verification attempts, and other operations.
  """

  @rate_limit_table :rate_limits

  @doc """
  Initialize the ETS table for rate limiting.
  Should be called from application.ex on startup.
  """
  def init do
    case :ets.whereis(@rate_limit_table) do
      :undefined ->
        :ets.new(@rate_limit_table, [:named_table, :public, :set, read_concurrency: true])

      _table ->
        :ok
    end
  end

  @doc """
  Check rate limit for OTP request endpoint.
  - Max 5 OTP requests per IP per hour
  - Max 3 OTP requests per email per hour
  """
  def check_otp_request_rate_limit(ip_address, email) do
    with :ok <- check_rate_limit("otp_request_ip_#{ip_address}", 5, 3600),
         :ok <- check_rate_limit("otp_request_email_#{email}", 3, 3600) do
      :ok
    end
  end

  @doc """
  Check rate limit for OTP verification endpoint.
  - Max 10 verification attempts per IP per hour
  - Max 5 verification attempts per email per 10 minutes
  - After 3 failed attempts per email, invalidates the OTP
  """
  def check_otp_verify_rate_limit(ip_address, email) do
    with :ok <- check_rate_limit("otp_verify_ip_#{ip_address}", 10, 3600),
         :ok <- check_rate_limit("otp_verify_email_#{email}", 5, 600) do
      :ok
    end
  end

  @doc """
  Track a failed OTP verification attempt.
  Returns {:error, :max_attempts_exceeded} if max attempts reached.
  """
  def track_otp_failed_attempt(email) do
    key = "otp_failed_#{email}"
    init()
    now = System.system_time(:second)
    # 10 minute window for failed attempts
    cutoff = now - 600

    attempts =
      case :ets.lookup(@rate_limit_table, key) do
        [{^key, timestamps}] -> Enum.filter(timestamps, &(&1 > cutoff))
        [] -> []
      end

    # Max 3 failed attempts before locking out
    if length(attempts) >= 3 do
      {:error, :max_attempts_exceeded}
    else
      new_attempts = [now | attempts]
      :ets.insert(@rate_limit_table, {key, new_attempts})
      :ok
    end
  end

  @doc """
  Clear failed attempt tracking for an email (call on successful verification).
  """
  def clear_otp_failed_attempts(email) do
    init()
    :ets.delete(@rate_limit_table, "otp_failed_#{email}")
    :ok
  end

  @doc """
  Clear all OTP-related rate limits for an email and IP.
  Useful for testing.
  """
  def clear_otp_rate_limits(email, ip_address \\ "127.0.0.1") do
    init()
    :ets.delete(@rate_limit_table, "otp_request_ip_#{ip_address}")
    :ets.delete(@rate_limit_table, "otp_request_email_#{email}")
    :ets.delete(@rate_limit_table, "otp_verify_ip_#{ip_address}")
    :ets.delete(@rate_limit_table, "otp_verify_email_#{email}")
    :ets.delete(@rate_limit_table, "otp_failed_#{email}")
    :ok
  end

  @doc """
  Generic rate limit checker using sliding window algorithm.
  Returns :ok if under limit, {:error, :rate_limit_exceeded} otherwise.
  """
  def check_rate_limit(key, max_attempts, window_seconds) do
    init()
    now = System.system_time(:second)
    cutoff = now - window_seconds

    attempts =
      case :ets.lookup(@rate_limit_table, key) do
        [{^key, timestamps}] -> Enum.filter(timestamps, &(&1 > cutoff))
        [] -> []
      end

    if length(attempts) >= max_attempts do
      {:error, :rate_limit_exceeded}
    else
      new_attempts = [now | attempts]
      :ets.insert(@rate_limit_table, {key, new_attempts})
      :ok
    end
  end

  @doc """
  Check rate limit for CLI auth start endpoint.
  - Max 10 code generation requests per IP per hour
  """
  def check_cli_auth_start_rate_limit(ip_address) do
    check_rate_limit("cli_auth_start_ip_#{ip_address}", 10, 3600)
  end

  @doc """
  Check rate limit for CLI auth poll endpoint.
  - Max 60 poll requests per IP per minute (allows polling every second)
  - Max 30 poll requests per code per minute
  """
  def check_cli_auth_poll_rate_limit(ip_address, code) do
    with :ok <- check_rate_limit("cli_auth_poll_ip_#{ip_address}", 60, 60),
         :ok <- check_rate_limit("cli_auth_poll_code_#{code}", 30, 60) do
      :ok
    end
  end

  @doc """
  Clear CLI auth rate limits for testing.
  """
  def clear_cli_auth_rate_limits(ip_address \\ "127.0.0.1", code \\ nil) do
    init()
    :ets.delete(@rate_limit_table, "cli_auth_start_ip_#{ip_address}")
    :ets.delete(@rate_limit_table, "cli_auth_poll_ip_#{ip_address}")

    if code do
      :ets.delete(@rate_limit_table, "cli_auth_poll_code_#{code}")
    end

    :ok
  end

  @doc """
  Clean up expired rate limit entries.
  Can be called periodically via a scheduled job.
  """
  def cleanup do
    init()
    now = System.system_time(:second)

    :ets.foldl(
      fn {key, timestamps}, acc ->
        # Keep only timestamps from last 2 hours
        recent = Enum.filter(timestamps, &(&1 > now - 7200))

        if recent == [] do
          :ets.delete(@rate_limit_table, key)
        else
          :ets.insert(@rate_limit_table, {key, recent})
        end

        acc
      end,
      :ok,
      @rate_limit_table
    )
  end
end
