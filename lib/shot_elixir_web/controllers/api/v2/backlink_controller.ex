defmodule ShotElixirWeb.Api.V2.BacklinkController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Backlinks
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  List backlinks (entities that mention the given entity) within the user's
  current campaign.
  """
  def index(conn, %{"entity_type" => entity_type, "id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id

    with true <- not is_nil(campaign_id) do
      backlinks = Backlinks.list_backlinks(campaign_id, String.downcase(entity_type), id)
      json(conn, %{backlinks: backlinks})
    else
      false ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})
    end
  end
end
