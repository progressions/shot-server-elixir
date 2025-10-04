defmodule ShotElixirWeb.UserSocket do
  use Phoenix.Socket

  require Logger

  alias ShotElixir.Guardian
  alias ShotElixir.Accounts

  # Channels
  channel "campaign:*", ShotElixirWeb.CampaignChannel
  channel "fight:*", ShotElixirWeb.FightChannel
  channel "user:*", ShotElixirWeb.UserChannel

  @impl true
  def connect(params, socket, connect_info) do
    Logger.debug(
      "[Cable] connect params=#{inspect(params)} connect_info=#{inspect(connect_info)}"
    )

    normalized_params = normalize_params(params)

    with token when is_binary(token) <- extract_token(normalized_params, connect_info),
         {:ok, user} <- authenticate(token) do
      Logger.debug(
        "[Cable] Authenticated user #{user.id} via #{token_source(normalized_params, connect_info)}"
      )

      socket =
        socket
        |> assign(:user_id, user.id)
        |> assign(:user, user)
        |> assign(:current_campaign_id, user.current_campaign_id)

      {:ok, socket}
    else
      {:error, reason} ->
        Logger.warning("[Cable] Authentication failed: #{inspect(reason)}")
        :error

      nil ->
        Logger.warning("[Cable] Missing authentication token in connect params")
        :error

      other ->
        Logger.warning("[Cable] Unknown authentication failure: #{inspect(other)}")
        :error
    end
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  # Private functions

  defp authenticate(token) do
    case Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        case Guardian.resource_from_claims(claims) do
          {:ok, user} ->
            case Accounts.get_user(user.id) do
              nil -> {:error, :user_not_found}
              user -> {:ok, user}
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  defp extract_token(params, connect_info) do
    [
      params["token"],
      params["jwt"],
      params["authorization"],
      params["Authorization"],
      bearer_token_from_headers(connect_info)
    ]
    |> Enum.find_value(&normalize_token/1)
  end

  defp normalize_params(params) when is_map(params) do
    Enum.reduce(params, %{}, fn {key, value}, acc ->
      Map.put(acc, to_string(key), value)
    end)
  end

  defp normalize_params(_), do: %{}

  defp bearer_token_from_headers(%{x_headers: headers}) when is_list(headers) do
    headers
    |> Enum.find_value(fn
      {"authorization", value} -> extract_bearer(value)
      {"Authorization", value} -> extract_bearer(value)
      _ -> nil
    end)
  end

  defp bearer_token_from_headers(_), do: nil

  defp normalize_token(nil), do: nil
  defp normalize_token(""), do: nil

  defp normalize_token(value) when is_binary(value) do
    extract_bearer(value) || value
  end

  defp normalize_token(_), do: nil

  defp extract_bearer("Bearer " <> token) when byte_size(token) > 0, do: token
  defp extract_bearer("bearer " <> token) when byte_size(token) > 0, do: token
  defp extract_bearer(_), do: nil

  defp token_source(params, connect_info) do
    cond do
      normalize_token(params["token"]) -> "query:token"
      normalize_token(params["jwt"]) -> "query:jwt"
      normalize_token(params["authorization"]) -> "query:authorization"
      normalize_token(params["Authorization"]) -> "query:Authorization"
      normalize_token(bearer_token_from_headers(connect_info)) -> "header:authorization"
      true -> "unknown"
    end
  end
end
