defmodule ShotElixirWeb.Api.V2.PartyController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Parties
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/parties
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    if current_user.current_campaign_id do
      # Verify user has access to campaign
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "Campaign not found"})

        campaign ->
          if authorize_campaign_access(campaign, current_user) do
            result =
              Parties.list_campaign_parties(
                current_user.current_campaign_id,
                params,
                current_user
              )

            conn
            |> put_view(ShotElixirWeb.Api.V2.PartyView)
            |> render("index.json",
              parties: result.parties,
              meta: result.meta,
              factions: result.factions
            )
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Access denied"})
          end
      end
    else
      conn
      |> put_status(:unprocessable_entity)
      |> json(%{error: "No active campaign selected"})
    end
  end

  # GET /api/v2/parties/:id
  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Parties.get_party(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        # Check campaign access
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_access(campaign, current_user) do
              conn
              |> put_view(ShotElixirWeb.Api.V2.PartyView)
              |> render("show.json", party: party)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Party not found"})
            end
        end
    end
  end

  # POST /api/v2/parties
  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Handle JSON string parsing like Rails
    parsed_params =
      case params do
        %{"party" => party_data} when is_binary(party_data) ->
          case Jason.decode(party_data) do
            {:ok, decoded} ->
              decoded

            {:error, _} ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Invalid party data format"})
              |> halt()
          end

        %{"party" => party_data} when is_map(party_data) ->
          party_data

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "Party parameters required"})
          |> halt()
      end

    if conn.halted do
      conn
    else
      # Add campaign_id from current campaign
      party_params = Map.put(parsed_params, "campaign_id", current_user.current_campaign_id)

      # Verify campaign access
      case Campaigns.get_campaign(current_user.current_campaign_id) do
        nil ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "No active campaign selected"})

        campaign ->
          if authorize_campaign_modification(campaign, current_user) do
            case Parties.create_party(party_params) do
              {:ok, party} ->
                # Handle image upload if present
                case conn.params["image"] do
                  %Plug.Upload{} = upload ->
                    case ShotElixir.Services.ImagekitService.upload_plug(upload) do
                      {:ok, upload_result} ->
                        case ShotElixir.ActiveStorage.attach_image(
                               "Party",
                               party.id,
                               upload_result
                             ) do
                          {:ok, _attachment} ->
                            party = Parties.get_party(party.id)

                            conn
                            |> put_status(:created)
                            |> put_view(ShotElixirWeb.Api.V2.PartyView)
                            |> render("show.json", party: party)

                          {:error, _changeset} ->
                            conn
                            |> put_status(:created)
                            |> put_view(ShotElixirWeb.Api.V2.PartyView)
                            |> render("show.json", party: party)
                        end

                      {:error, _reason} ->
                        conn
                        |> put_status(:created)
                        |> put_view(ShotElixirWeb.Api.V2.PartyView)
                        |> render("show.json", party: party)
                    end

                  _ ->
                    conn
                    |> put_status(:created)
                    |> put_view(ShotElixirWeb.Api.V2.PartyView)
                    |> render("show.json", party: party)
                end

              {:error, changeset} ->
                conn
                |> put_status(:unprocessable_entity)
                |> put_view(ShotElixirWeb.Api.V2.PartyView)
                |> render("error.json", changeset: changeset)
            end
          else
            conn
            |> put_status(:forbidden)
            |> json(%{error: "Only gamemaster can create parties"})
          end
      end
    end
  end

  # PATCH/PUT /api/v2/parties/:id
  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case Parties.get_party(params["id"]) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        # Check campaign access
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # Handle JSON string parsing like Rails
              parsed_params =
                case params do
                  %{"party" => party_data} when is_binary(party_data) ->
                    case Jason.decode(party_data) do
                      {:ok, decoded} ->
                        decoded

                      {:error, _} ->
                        conn
                        |> put_status(:bad_request)
                        |> json(%{error: "Invalid party data format"})
                        |> halt()
                    end

                  %{"party" => party_data} when is_map(party_data) ->
                    party_data

                  _ ->
                    conn
                    |> put_status(:bad_request)
                    |> json(%{error: "Party parameters required"})
                    |> halt()
                end

              if conn.halted do
                conn
              else
                # Handle image upload if present
                case conn.params["image"] do
                  %Plug.Upload{} = upload ->
                    # Upload image to ImageKit
                    case ShotElixir.Services.ImagekitService.upload_plug(upload) do
                      {:ok, upload_result} ->
                        # Attach image to party via ActiveStorage
                        case ShotElixir.ActiveStorage.attach_image(
                               "Party",
                               party.id,
                               upload_result
                             ) do
                          {:ok, _attachment} ->
                            # Reload party to get fresh data after image attachment
                            party = Parties.get_party(party.id)
                            # Continue with party update
                            case Parties.update_party(party, parsed_params) do
                              {:ok, party} ->
                                conn
                                |> put_view(ShotElixirWeb.Api.V2.PartyView)
                                |> render("show.json", party: party)

                              {:error, changeset} ->
                                conn
                                |> put_status(:unprocessable_entity)
                                |> put_view(ShotElixirWeb.Api.V2.PartyView)
                                |> render("error.json", changeset: changeset)
                            end

                          {:error, changeset} ->
                            conn
                            |> put_status(:unprocessable_entity)
                            |> put_view(ShotElixirWeb.Api.V2.PartyView)
                            |> render("error.json", changeset: changeset)
                        end

                      {:error, reason} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> json(%{error: "Failed to upload image: #{inspect(reason)}"})
                    end

                  _ ->
                    # No image upload, just update party
                    case Parties.update_party(party, parsed_params) do
                      {:ok, party} ->
                        conn
                        |> put_view(ShotElixirWeb.Api.V2.PartyView)
                        |> render("show.json", party: party)

                      {:error, changeset} ->
                        conn
                        |> put_status(:unprocessable_entity)
                        |> put_view(ShotElixirWeb.Api.V2.PartyView)
                        |> render("error.json", changeset: changeset)
                    end
                end
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Party not found"})
            end
        end
    end
  end

  # DELETE /api/v2/parties/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Parties.get_party(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        # Check campaign access
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Parties.delete_party(party) do
                {:ok, _party} ->
                  send_resp(conn, :no_content, "")

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to delete party"})
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Party not found"})
            end
        end
    end
  end

  # DELETE /api/v2/parties/:id/remove_image
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Parties.get_party(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        # Check campaign access
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # Remove image from ActiveStorage
              case ShotElixir.ActiveStorage.delete_image("Party", party.id) do
                {:ok, _} ->
                  # Reload party to get fresh data after image removal
                  updated_party = Parties.get_party(party.id)

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("show.json", party: updated_party)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Party not found"})
            end
        end
    end
  end

  # POST /api/v2/parties/:party_id/add_to_fight/:fight_id
  def add_to_fight(conn, %{"party_id" => party_id, "fight_id" => fight_id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %{} = party <- Parties.get_party(party_id),
         %{} = campaign <- Campaigns.get_campaign(party.campaign_id),
         :ok <- authorize_campaign_modification(campaign, current_user),
         %{} = fight <- ShotElixir.Fights.get_fight(fight_id),
         :ok <- validate_same_campaign(party.campaign_id, fight.campaign_id) do
      # Add party members to fight (this would need implementation in Fights context)
      # For now, just return the party
      conn
      |> put_view(ShotElixirWeb.Api.V2.PartyView)
      |> render("show.json", party: party)
    else
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party or fight not found"})

      {:error, :forbidden} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only gamemaster can add parties to fights"})

      {:error, :different_campaigns} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Party and fight must be in the same campaign"})

      _ ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to add party to fight"})
    end
  end

  # POST /api/v2/parties/:id/members
  def add_member(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    id = params["id"] || params["party_id"]

    case Parties.get_party(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        # Check campaign access
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              member_attrs = %{
                "character_id" => params["character_id"],
                "vehicle_id" => params["vehicle_id"]
              }

              case Parties.add_member(id, member_attrs) do
                {:ok, _membership} ->
                  party = Parties.get_party!(id)

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("show.json", party: party)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Party not found"})
            end
        end
    end
  end

  # POST /api/v2/parties/:id/duplicate
  def duplicate(conn, %{"party_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, campaign_id} <- ensure_campaign(current_user),
         %{} = party <- Parties.get_party(id),
         true <- party.campaign_id == campaign_id,
         campaign <- Campaigns.get_campaign(campaign_id),
         true <- authorize_campaign_modification(campaign, current_user),
         {:ok, new_party} <- Parties.duplicate_party(party) do
      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.PartyView)
      |> render("show.json", party: new_party)
    else
      {:error, :no_campaign} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      false ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Only campaign owners, admins, or gamemasters can duplicate parties"})

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.PartyView)
        |> render("error.json", changeset: changeset)
    end
  end

  defp ensure_campaign(user) do
    if user.current_campaign_id do
      {:ok, user.current_campaign_id}
    else
      {:error, :no_campaign}
    end
  end

  # DELETE /api/v2/parties/:id/members/:membership_id
  def remove_member(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    party_id = params["party_id"]
    membership_id = params["membership_id"]

    case Parties.get_party(party_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        # Check campaign access
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
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
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Party not found"})
            end
        end
    end
  end

  # =============================================================================
  # Party Composition / Slot Endpoints
  # =============================================================================

  # GET /api/v2/parties/templates
  def list_templates(conn, _params) do
    templates = Parties.list_templates()

    conn
    |> put_view(ShotElixirWeb.Api.V2.PartyView)
    |> render("templates.json", templates: templates)
  end

  # POST /api/v2/parties/:id/apply_template
  def apply_template(conn, %{"party_id" => party_id, "template_key" => template_key}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Parties.get_party(party_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Parties.apply_template(party_id, template_key) do
                {:ok, updated_party} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("show.json", party: updated_party)

                {:error, :template_not_found} ->
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Template not found"})

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can modify party composition"})
            end
        end
    end
  end

  # POST /api/v2/parties/:id/slots
  def add_slot(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    party_id = params["party_id"]

    case Parties.get_party(party_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              slot_attrs = %{
                "role" => params["role"],
                "default_mook_count" => params["default_mook_count"],
                "character_id" => params["character_id"]
              }

              case Parties.add_slot(party_id, slot_attrs) do
                {:ok, _slot} ->
                  updated_party = Parties.get_party!(party_id)

                  conn
                  |> put_status(:created)
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("show.json", party: updated_party)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can modify party composition"})
            end
        end
    end
  end

  # PATCH /api/v2/parties/:id/slots/:slot_id
  def update_slot(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    party_id = params["party_id"]
    slot_id = params["slot_id"]

    case Parties.get_party(party_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              # Only include fields that are actually provided in params
              # Use Map.has_key? to distinguish between "not provided" and "explicitly set to null"
              # This allows clearing character_id/vehicle_id by sending null
              slot_attrs =
                Enum.reduce(
                  ["character_id", "vehicle_id", "default_mook_count"],
                  %{},
                  fn key, acc ->
                    if Map.has_key?(params, key) do
                      Map.put(acc, key, params[key])
                    else
                      acc
                    end
                  end
                )

              case Parties.update_slot(party_id, slot_id, slot_attrs) do
                {:ok, _slot} ->
                  updated_party = Parties.get_party!(party_id)

                  conn
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("show.json", party: updated_party)

                {:error, :not_found} ->
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Slot not found"})

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("error.json", changeset: changeset)
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can modify party composition"})
            end
        end
    end
  end

  # DELETE /api/v2/parties/:id/slots/:slot_id
  def remove_slot(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    party_id = params["party_id"]
    slot_id = params["slot_id"]

    case Parties.get_party(party_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Parties.remove_slot(party_id, slot_id) do
                {:ok, _} ->
                  send_resp(conn, :no_content, "")

                {:error, :not_found} ->
                  conn
                  |> put_status(:not_found)
                  |> json(%{error: "Slot not found"})

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to remove slot"})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can modify party composition"})
            end
        end
    end
  end

  # POST /api/v2/parties/:id/reorder_slots
  def reorder_slots(conn, %{"party_id" => party_id, "slot_ids" => slot_ids}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Parties.get_party(party_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Party not found"})

      party ->
        case Campaigns.get_campaign(party.campaign_id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Party not found"})

          campaign ->
            if authorize_campaign_modification(campaign, current_user) do
              case Parties.reorder_slots(party_id, slot_ids) do
                {:ok, updated_party} ->
                  conn
                  |> put_view(ShotElixirWeb.Api.V2.PartyView)
                  |> render("show.json", party: updated_party)

                {:error, _} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> json(%{error: "Failed to reorder slots"})
              end
            else
              conn
              |> put_status(:forbidden)
              |> json(%{error: "Only gamemaster can modify party composition"})
            end
        end
    end
  end

  # Private helper functions
  defp authorize_campaign_access(campaign, user) do
    campaign.user_id == user.id || user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id)) ||
      Campaigns.is_member?(campaign.id, user.id)
  end

  defp authorize_campaign_modification(campaign, user) do
    campaign.user_id == user.id || user.admin ||
      (user.gamemaster && Campaigns.is_member?(campaign.id, user.id))
  end

  defp validate_same_campaign(campaign_id1, campaign_id2) do
    if campaign_id1 == campaign_id2 do
      :ok
    else
      {:error, :different_campaigns}
    end
  end
end
