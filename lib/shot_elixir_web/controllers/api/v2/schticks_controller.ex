defmodule ShotElixirWeb.Api.V2.SchticksController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Schticks
  alias ShotElixir.Campaigns
  alias ShotElixir.Guardian

  action_fallback ShotElixirWeb.FallbackController

  # GET /api/v2/schticks
  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_current_campaign(current_user) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      campaign ->
        result = Schticks.list_campaign_schticks(campaign.id, params, current_user)
        categories_result = Schticks.get_categories(campaign.id, params)
        paths_result = Schticks.get_paths(campaign.id, params)

        conn
        |> put_view(ShotElixirWeb.Api.V2.SchticksView)
        |> render("index.json",
          schticks: result.schticks,
          meta: result.meta,
          categories: categories_result.general ++ categories_result.core,
          paths: paths_result.paths
        )
    end
  end

  # DELETE /api/v2/schticks/:id/image
  def remove_image(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_current_campaign(current_user) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      campaign ->
        case Schticks.get_schtick(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Schtick not found"})

          schtick ->
            if schtick.campaign_id == campaign.id do
              # Image removal handled by Rails Active Storage; mirror response for parity.
              conn
              |> put_view(ShotElixirWeb.Api.V2.SchticksView)
              |> render("show.json", schtick: schtick)
            else
              conn
              |> put_status(:not_found)
              |> json(%{error: "Schtick not found"})
            end
        end
    end
  end

  # GET /api/v2/schticks/batch
  def batch(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_current_campaign(current_user) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      campaign ->
        unless Map.has_key?(params, "ids") do
          conn
          |> put_status(:bad_request)
          |> json(%{error: "ids parameter is required"})
        else
          if params["ids"] == "" do
            conn
            |> put_status(:ok)
            |> json(%{
              schticks: [],
              categories: [],
              meta: %{
                current_page: 1,
                next_page: nil,
                prev_page: nil,
                total_pages: 1,
                total_count: 0
              }
            })
          else
            ids = String.split(params["ids"], ",") |> Enum.map(&String.trim/1)
            result = Schticks.get_schticks_batch(campaign.id, ids, params)

            conn
            |> put_view(ShotElixirWeb.Api.V2.SchticksView)
            |> render("batch.json", data: result)
          end
        end
    end
  end

  # GET /api/v2/schticks/categories
  def categories(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_current_campaign(current_user) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      campaign ->
        result = Schticks.get_categories(campaign.id, params)
        json(conn, result)
    end
  end

  # GET /api/v2/schticks/paths
  def paths(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_current_campaign(current_user) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      campaign ->
        result = Schticks.get_paths(campaign.id, params)
        json(conn, result)
    end
  end

  # GET /api/v2/schticks/:id
  def show(conn, %{"id" => id}) do
    schtick = Schticks.get_schtick(id)

    if schtick do
      conn
      |> put_view(ShotElixirWeb.Api.V2.SchticksView)
      |> render("show.json", schtick: schtick)
    else
      conn
      |> put_status(:not_found)
      |> json(%{error: "Schtick not found"})
    end
  end

  # POST /api/v2/schticks
  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_current_campaign(current_user) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      campaign ->
        # Handle JSON string parsing like Rails
        parsed_params =
          case params do
            %{"schtick" => schtick_data} when is_binary(schtick_data) ->
              case Jason.decode(schtick_data) do
                {:ok, decoded} ->
                  decoded

                {:error, _} ->
                  conn
                  |> put_status(:bad_request)
                  |> json(%{error: "Invalid schtick data format"})
                  |> halt()
              end

            %{"schtick" => schtick_data} when is_map(schtick_data) ->
              schtick_data

            _ ->
              conn
              |> put_status(:bad_request)
              |> json(%{error: "Schtick parameters required"})
              |> halt()
          end

        if conn.halted do
          conn
        else
          # Add campaign_id
          schtick_params = Map.put(parsed_params, "campaign_id", campaign.id)

          case Schticks.create_schtick(schtick_params) do
            {:ok, schtick} ->
              conn
              |> put_status(:created)
              |> put_view(ShotElixirWeb.Api.V2.SchticksView)
              |> render("show.json", schtick: schtick)

            {:error, changeset} ->
              conn
              |> put_status(:unprocessable_entity)
              |> put_view(ShotElixirWeb.Api.V2.SchticksView)
              |> render("error.json", changeset: changeset)
          end
        end
    end
  end

  # PATCH/PUT /api/v2/schticks/:id
  def update(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_current_campaign(current_user) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      _campaign ->
        case Schticks.get_schtick(params["id"]) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Schtick not found"})

          schtick ->
            # Handle JSON string parsing like Rails
            parsed_params =
              case params do
                %{"schtick" => schtick_data} when is_binary(schtick_data) ->
                  case Jason.decode(schtick_data) do
                    {:ok, decoded} ->
                      decoded

                    {:error, _} ->
                      conn
                      |> put_status(:bad_request)
                      |> json(%{error: "Invalid schtick data format"})
                      |> halt()
                  end

                %{"schtick" => schtick_data} when is_map(schtick_data) ->
                  schtick_data

                _ ->
                  conn
                  |> put_status(:bad_request)
                  |> json(%{error: "Schtick parameters required"})
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
                      # Attach image to schtick via ActiveStorage
                      case ShotElixir.ActiveStorage.attach_image(
                             "Schtick",
                             schtick.id,
                             upload_result
                           ) do
                        {:ok, _attachment} ->
                          # Reload schtick to get fresh data after image attachment
                          schtick = Schticks.get_schtick(schtick.id)
                          # Continue with schtick update
                          case Schticks.update_schtick(schtick, parsed_params) do
                            {:ok, updated_schtick} ->
                              conn
                              |> put_view(ShotElixirWeb.Api.V2.SchticksView)
                              |> render("show.json", schtick: updated_schtick)

                            {:error, changeset} ->
                              conn
                              |> put_status(:unprocessable_entity)
                              |> put_view(ShotElixirWeb.Api.V2.SchticksView)
                              |> render("error.json", changeset: changeset)
                          end

                        {:error, changeset} ->
                          conn
                          |> put_status(:unprocessable_entity)
                          |> put_view(ShotElixirWeb.Api.V2.SchticksView)
                          |> render("error.json", changeset: changeset)
                      end

                    {:error, reason} ->
                      conn
                      |> put_status(:unprocessable_entity)
                      |> json(%{error: "Failed to upload image: #{inspect(reason)}"})
                  end

                _ ->
                  # No image upload, just update schtick
                  case Schticks.update_schtick(schtick, parsed_params) do
                    {:ok, updated_schtick} ->
                      conn
                      |> put_view(ShotElixirWeb.Api.V2.SchticksView)
                      |> render("show.json", schtick: updated_schtick)

                    {:error, changeset} ->
                      conn
                      |> put_status(:unprocessable_entity)
                      |> put_view(ShotElixirWeb.Api.V2.SchticksView)
                      |> render("error.json", changeset: changeset)
                  end
              end
            end
        end
    end
  end

  # POST /api/v2/schticks/import
  # Maximum YAML size: 1MB (protection against DoS via large payloads)
  @max_yaml_size 1_000_000

  def import(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_current_campaign(current_user) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      campaign ->
        # Get YAML from params
        yaml_content =
          case params do
            %{"schtick" => %{"yaml" => yaml}} -> yaml
            %{"yaml" => yaml} -> yaml
            _ -> nil
          end

        cond do
          is_nil(yaml_content) ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "YAML content is required"})

          byte_size(yaml_content) > @max_yaml_size ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: "YAML content too large (max 1MB)"})

          true ->
            parse_and_import_yaml(conn, yaml_content, campaign)
        end
    end
  end

  defp parse_and_import_yaml(conn, yaml_content, campaign) do
    case YamlElixir.read_from_string(yaml_content) do
      {:ok, data} ->
        case ShotElixir.Services.ImportSchticks.call(data, campaign) do
          {:ok, %{successful: successful, failed: 0}} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Successfully imported #{successful} schticks",
              successful: successful,
              failed: 0
            })

          {:ok, %{successful: successful, failed: failed}} ->
            conn
            |> put_status(:ok)
            |> json(%{
              message: "Imported #{successful} schticks with #{failed} failures",
              successful: successful,
              failed: failed
            })

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Import failed: #{reason}"})
        end

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid YAML format: #{inspect(reason)}"})
    end
  end

  # DELETE /api/v2/schticks/:id
  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case get_current_campaign(current_user) do
      nil ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No active campaign selected"})

      _campaign ->
        case Schticks.get_schtick(id) do
          nil ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "Schtick not found"})

          schtick ->
            case Schticks.delete_schtick(schtick) do
              {:ok, _schtick} ->
                send_resp(conn, :no_content, "")

              {:error, :has_dependents} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Cannot delete schtick with dependent schticks"})

              {:error, _} ->
                conn
                |> put_status(:unprocessable_entity)
                |> json(%{error: "Failed to delete schtick"})
            end
        end
    end
  end

  # Helper function to get current campaign
  defp get_current_campaign(user) do
    if user.current_campaign_id do
      Campaigns.get_campaign(user.current_campaign_id)
    else
      nil
    end
  end
end
