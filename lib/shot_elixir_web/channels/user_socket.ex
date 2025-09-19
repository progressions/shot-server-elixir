defmodule ShotElixirWeb.UserSocket do
  use Phoenix.Socket

  alias ShotElixir.Guardian
  alias ShotElixir.Accounts

  # Channels
  channel "campaign:*", ShotElixirWeb.CampaignChannel
  channel "fight:*", ShotElixirWeb.FightChannel
  channel "user:*", ShotElixirWeb.UserChannel

  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    case authenticate(token) do
      {:ok, user} ->
        socket =
          socket
          |> assign(:user_id, user.id)
          |> assign(:user, user)
          |> assign(:current_campaign_id, user.current_campaign_id)

        {:ok, socket}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    :error
  end

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  # Private functions

  defp authenticate(token) do
    case Guardian.decode_and_verify(token) do
      {:ok, claims} ->
        case Guardian.resource_from_claims(claims) do
          {:ok, user} ->
            # Refresh user from database to get latest data
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
end