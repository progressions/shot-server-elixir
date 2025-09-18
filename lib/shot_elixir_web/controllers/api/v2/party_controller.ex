defmodule ShotElixirWeb.Api.V2.PartyController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Parties
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/parties
  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      parties = Parties.list_parties(current_user.current_campaign_id)
      render(conn, :index, parties: parties)
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/parties/:id
  def show(conn, %{"id" => id}) do
    party = Parties.get_party(id)

    if party do
      render(conn, :show, party: party)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Party not found"})
    end
  end

  # POST /api/v2/parties
  def create(conn, %{"party" => party_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Add campaign_id if not provided
    party_params = Map.put_new(party_params, "campaign_id", current_user.current_campaign_id)

    case Parties.create_party(party_params) do
      {:ok, party} ->
        conn
        |> put_status(:created)
        |> render(:show, party: party)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:error, changeset: changeset)
    end
  end

  # PATCH/PUT /api/v2/parties/:id
  def update(conn, %{"id" => id, "party" => party_params}) do
    party = Parties.get_party(id)

    cond do
      party == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      true ->
        case Parties.update_party(party, party_params) do
          {:ok, party} ->
            render(conn, :show, party: party)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:error, changeset: changeset)
        end
    end
  end

  # DELETE /api/v2/parties/:id
  def delete(conn, %{"id" => id}) do
    party = Parties.get_party(id)

    cond do
      party == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      true ->
        case Parties.delete_party(party) do
          {:ok, _party} ->
            send_resp(conn, :no_content, "")

          {:error, _} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to delete party"})
        end
    end
  end

  # POST /api/v2/parties/:id/members
  def add_member(conn, params) do
    id = params["id"] || params["party_id"]
    party = Parties.get_party(id)

    cond do
      party == nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      true ->
        member_attrs = %{
          "character_id" => params["character_id"],
          "vehicle_id" => params["vehicle_id"]
        }

        case Parties.add_member(id, member_attrs) do
          {:ok, _membership} ->
            party = Parties.get_party!(id)
            render(conn, :show, party: party)

          {:error, changeset} ->
            conn
            |> put_status(:unprocessable_entity)
            |> render(:error, changeset: changeset)
        end
    end
  end

  # DELETE /api/v2/parties/:id/members/:membership_id
  def remove_member(conn, %{"id" => _id, "membership_id" => membership_id}) do
    case Parties.remove_member(membership_id) do
      {:ok, _} ->
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Membership not found"})

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to remove member"})
    end
  end
end
