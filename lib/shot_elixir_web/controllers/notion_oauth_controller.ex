defmodule ShotElixirWeb.NotionOAuthController do
  @moduledoc """
  Handles Notion OAuth2 flow for campaign integration.
  Uses the Public Integration (OAuth) model to authorize access to a user's Notion workspace.
  """
  use ShotElixirWeb, :controller
  require Logger
  alias ShotElixir.Campaigns
  alias ShotElixir.Accounts
  alias ShotElixir.Notion

  @notion_auth_url "https://api.notion.com/v1/oauth/authorize"
  @notion_token_url "https://api.notion.com/v1/oauth/token"

  @doc """
  Initiates the Notion OAuth flow.
  Redirects to Notion's OAuth consent screen.

  Expected params:
    - campaign_id: The ID of the campaign to link
  """
  def authorize(conn, %{"campaign_id" => campaign_id}) do
    # Verify user is authenticated and owns the campaign
    user_id =
      case Guardian.Plug.current_resource(conn) do
        %Accounts.User{id: id} -> id
        _ -> nil
      end

    if user_id do
      case Campaigns.get_campaign(campaign_id) do
        %Campaigns.Campaign{user_id: ^user_id} ->
          client_id =
            fetch_notion_oauth_config_value!(
              :client_id,
              "NOTION_CLIENT_ID",
              "Notion OAuth client_id not configured"
            )

          redirect_uri =
            fetch_notion_oauth_config_value!(
              :redirect_uri,
              "NOTION_REDIRECT_URI",
              "Notion OAuth redirect_uri not configured"
            )

          # State parameter to prevent CSRF and pass context
          state =
            Jason.encode!(%{
              campaign_id: campaign_id,
              user_id: user_id,
              nonce: :crypto.strong_rand_bytes(16) |> Base.encode64()
            })
            |> Base.encode64()

          params = %{
            client_id: client_id,
            response_type: "code",
            owner: "user",
            redirect_uri: redirect_uri,
            state: state
          }

          auth_url = @notion_auth_url <> "?" <> URI.encode_query(params)

          Logger.info(
            "NotionOAuth: Redirecting user #{user_id} for campaign #{campaign_id} to Notion OAuth"
          )

          redirect(conn, external: auth_url)

        _ ->
          conn
          |> put_status(:forbidden)
          |> json(%{error: "You do not have permission to modify this campaign"})
      end
    else
      conn
      |> put_status(:unauthorized)
      |> json(%{error: "Authentication required"})
    end
  end

  def authorize(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing campaign_id parameter"})
  end

  @doc """
  Handles the OAuth callback from Notion.
  Exchanges the temporary code for an access token and updates the campaign.
  """
  def callback(conn, %{"code" => code, "state" => encoded_state}) do
    with {:ok, state_json} <- Base.decode64(encoded_state),
         {:ok, state} <- Jason.decode(state_json),
         %{
           "campaign_id" => campaign_id,
           "user_id" => user_id
         } = state,
         # Verify campaign ownership again
         %Campaigns.Campaign{user_id: ^user_id} = campaign <- Campaigns.get_campaign(campaign_id),
         {:ok, token_data} <- exchange_code_for_token(code) do
      # Update campaign with Notion credentials
      update_params = %{
        notion_access_token: token_data["access_token"],
        notion_bot_id: token_data["bot_id"],
        notion_workspace_name: token_data["workspace_name"],
        notion_workspace_icon: token_data["workspace_icon"],
        notion_owner: token_data["owner"],
        # Don't overwrite database_ids if they exist, but initialize if nil
        notion_database_ids: campaign.notion_database_ids || %{},
        # Set status to working on successful connection
        notion_status: "working"
      }

      case Campaigns.update_campaign(campaign, update_params) do
        {:ok, updated_campaign} ->
          Logger.info(
            "NotionOAuth: Successfully linked campaign #{campaign_id} to Notion workspace #{token_data["workspace_name"]}"
          )

          # Queue email notification for successful connection
          Notion.queue_status_change_email(updated_campaign.id, "working")

          # Redirect to the frontend campaign page
          frontend_url = Application.get_env(:shot_elixir, :frontend_url, "http://localhost:3001")

          redirect(conn,
            external: "#{frontend_url}/campaigns/#{campaign_id}?notion_connected=true"
          )

        {:error, changeset} ->
          Logger.error("NotionOAuth: Failed to update campaign: #{inspect(changeset)}")

          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to save Notion credentials"})
      end
    else
      %Campaigns.Campaign{} ->
        Logger.warning("NotionOAuth: Campaign mismatch or unauthorized access")
        conn |> put_status(:forbidden) |> json(%{error: "Unauthorized"})

      {:error, reason} ->
        Logger.error("NotionOAuth: Error processing callback: #{inspect(reason)}")
        conn |> put_status(:bad_request) |> json(%{error: "Invalid request"})

      nil ->
        Logger.error("NotionOAuth: Campaign not found")
        conn |> put_status(:not_found) |> json(%{error: "Campaign not found"})
    end
  end

  def callback(conn, %{"error" => error}) do
    Logger.warning("NotionOAuth: Notion returned error: #{error}")

    conn
    |> put_status(:bad_request)
    |> json(%{error: "Notion authorization failed: #{error}"})
  end

  defp exchange_code_for_token(code) do
    client_id =
      fetch_notion_oauth_config_value!(
        :client_id,
        "NOTION_CLIENT_ID",
        "Notion OAuth client_id missing"
      )

    client_secret =
      fetch_notion_oauth_config_value!(
        :client_secret,
        "NOTION_CLIENT_SECRET",
        "Notion OAuth client_secret missing"
      )

    redirect_uri =
      fetch_notion_oauth_config_value!(
        :redirect_uri,
        "NOTION_REDIRECT_URI",
        "Notion OAuth redirect_uri missing"
      )

    # Notion uses Basic Auth for the token endpoint
    auth_header = "Basic " <> Base.encode64("#{client_id}:#{client_secret}")

    body = %{
      grant_type: "authorization_code",
      code: code,
      redirect_uri: redirect_uri
    }

    case Req.post(@notion_token_url, json: body, headers: [{"Authorization", auth_header}]) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: status, body: body}} ->
        Logger.error("NotionOAuth: Token exchange failed with status #{status}: #{inspect(body)}")
        {:error, "Token exchange failed"}

      {:error, reason} ->
        Logger.error("NotionOAuth: Token exchange network error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_notion_oauth_config_value!(key, env_var, error_message) do
    # Try config first, then env var
    config = Application.get_env(:shot_elixir, :notion_oauth) || []

    value = Keyword.get(config, key) || System.get_env(env_var)

    if is_nil(value) or value == "" do
      raise ArgumentError, error_message
    end

    value
  end
end
