defmodule ShotElixirWeb.Api.V2.CharacterController do
  require Logger
  use ShotElixirWeb, :controller

  alias ShotElixir.Campaigns
  alias ShotElixir.Characters
  alias ShotElixir.Characters.Character
  alias ShotElixir.Guardian
  alias ShotElixir.Workers.SyncCharacterToNotionWorker

  action_fallback ShotElixirWeb.FallbackController

  def index(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    # Get current campaign from user or params
    campaign_id = current_user.current_campaign_id || params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No current campaign set"})
    else
      result = Characters.list_campaign_characters(campaign_id, params, current_user)

      Logger.debug(fn ->
        %{
          message: "Characters#index",
          params: params,
          campaign_id: campaign_id,
          returned: length(result.characters)
        }
        |> Jason.encode!()
      end)

      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("index.json",
        characters: result.characters,
        meta: result.meta,
        archetypes: result.archetypes,
        factions: result.factions
      )
    end
  end

  def show(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_access(character, current_user) do
      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("show.json", character: character)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def create(conn, %{"character" => character_params}) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id || character_params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No current campaign set"})
    else
      params =
        character_params
        |> Map.put("campaign_id", campaign_id)
        |> Map.put("user_id", current_user.id)

      case Characters.create_character(params) do
        {:ok, character} ->
          # Handle image upload if present
          case conn.params["image"] do
            %Plug.Upload{} = upload ->
              case ShotElixir.Services.ImagekitService.upload_plug(upload) do
                {:ok, upload_result} ->
                  case ShotElixir.ActiveStorage.attach_image(
                         "Character",
                         character.id,
                         upload_result
                       ) do
                    {:ok, _attachment} ->
                      character = Characters.get_character(character.id)

                      conn
                      |> put_status(:created)
                      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
                      |> render("show.json", character: character)

                    {:error, _changeset} ->
                      conn
                      |> put_status(:created)
                      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
                      |> render("show.json", character: character)
                  end

                {:error, _reason} ->
                  conn
                  |> put_status(:created)
                  |> put_view(ShotElixirWeb.Api.V2.CharacterView)
                  |> render("show.json", character: character)
              end

            _ ->
              conn
              |> put_status(:created)
              |> put_view(ShotElixirWeb.Api.V2.CharacterView)
              |> render("show.json", character: character)
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.CharacterView)
          |> render("error.json", changeset: changeset)
      end
    end
  end

  def update(conn, %{"id" => id, "character" => character_params}) do
    current_user = Guardian.Plug.current_resource(conn)

    # Parse character_params if it's a JSON string (from multipart/form-data)
    parsed_params =
      case character_params do
        params when is_binary(params) ->
          case Jason.decode(params) do
            {:ok, decoded} -> decoded
            {:error, _} -> %{}
          end

        params when is_map(params) ->
          params

        _ ->
          %{}
      end

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_edit(character, current_user) do
      # Handle image upload if present
      case conn.params["image"] do
        %Plug.Upload{} = upload ->
          # Upload image to ImageKit
          case ShotElixir.Services.ImagekitService.upload_plug(upload) do
            {:ok, upload_result} ->
              # Attach image to character via ActiveStorage
              case ShotElixir.ActiveStorage.attach_image("Character", character.id, upload_result) do
                {:ok, _attachment} ->
                  # Reload character to get fresh data after image attachment
                  character = Characters.get_character(character.id)
                  # Continue with character update
                  update_character_with_params(conn, character, parsed_params)

                {:error, changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.CharacterView)
                  |> render("error.json", changeset: changeset)
              end

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "Image upload failed: #{inspect(reason)}"})
          end

        _ ->
          # No image uploaded, proceed with normal update
          update_character_with_params(conn, character, parsed_params)
      end
    else
      nil ->
        {:error, :not_found}

      {:error, :forbidden} ->
        {:error, :forbidden}

      {:error, :unauthorized} ->
        {:error, :forbidden}
    end
  end

  defp update_character_with_params(conn, character, parsed_params) do
    # Continue with normal update
    case Characters.update_character(character, parsed_params) do
      {:ok, final_character} ->
        # Broadcasting now happens automatically in Characters context

        # Queue Notion sync
        %{"character_id" => final_character.id}
        |> SyncCharacterToNotionWorker.new()
        |> Oban.insert()

        conn
        |> put_view(ShotElixirWeb.Api.V2.CharacterView)
        |> render("show.json", character: final_character)

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(ShotElixirWeb.Api.V2.CharacterView)
        |> render("error.json", changeset: changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_edit(character, current_user),
         {:ok, _} <- Characters.delete_character(character) do
      # Broadcasting now happens automatically in Characters context
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Custom endpoints
  def duplicate(conn, %{"character_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_access(character, current_user),
         {:ok, new_character} <- Characters.duplicate_character(character, current_user) do
      # Queue Notion sync
      %{"character_id" => new_character.id}
      |> SyncCharacterToNotionWorker.new()
      |> Oban.insert()

      # Use source character's image_url for immediate display
      # (the actual image copy happens async via ImageCopyWorker)
      new_character_with_image = %{new_character | image_url: character.image_url}

      conn
      |> put_status(:created)
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("show.json", character: new_character_with_image)
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync(conn, %{"id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_edit(character, current_user) do
      # Queue Notion sync
      %{"character_id" => character.id}
      |> SyncCharacterToNotionWorker.new()
      |> Oban.insert()

      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("sync.json", character: character, status: "queued")
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def create_notion_page(conn, %{"character_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_edit(character, current_user) do
      # Check if character already has a Notion page
      if character.notion_page_id do
        conn
        |> put_status(:conflict)
        |> json(%{error: "Character already has a Notion page linked"})
      else
        # Create new Notion page
        case ShotElixir.Services.NotionService.create_notion_from_character(character) do
          {:ok, page} ->
            Logger.debug("Notion page created with ID: #{inspect(page["id"])}")

            # Reload character to get updated notion_page_id
            updated_character = Characters.get_character(id)

            Logger.debug(
              "Character after reload - notion_page_id: #{inspect(updated_character.notion_page_id)}"
            )

            conn
            |> put_status(:created)
            |> put_view(ShotElixirWeb.Api.V2.CharacterView)
            |> render("show.json", character: updated_character)

          {:error, _reason} ->
            # Avoid logging potentially sensitive HTTP request metadata (e.g., Authorization headers)
            Logger.error("Failed to create Notion page")

            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Failed to create Notion page"})
        end
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def pdf(conn, %{"character_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    case Characters.get_character(id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Character not found"})

      character ->
        # Check authorization
        case authorize_character_access(character, current_user) do
          :ok ->
            # Generate PDF
            case ShotElixir.Services.PdfService.character_to_pdf(character) do
              {:ok, temp_path} ->
                filename =
                  character.name
                  |> String.replace(~r/[^\w\s-]/, "")
                  |> String.downcase()
                  |> String.replace(~r/\s+/, "_")
                  |> String.slice(0..100)
                  |> Kernel.<>("_character_sheet.pdf")

                try do
                  conn
                  |> put_resp_content_type("application/pdf")
                  |> put_resp_header(
                    "content-disposition",
                    "attachment; filename=\"#{filename}\""
                  )
                  |> send_file(200, temp_path)
                after
                  # Always clean up temp file, even if send_file fails
                  File.rm(temp_path)
                end

              {:error, reason} ->
                conn
                |> put_status(:internal_server_error)
                |> json(%{error: "Failed to generate PDF: #{reason}"})
            end

          {:error, :forbidden} ->
            conn
            |> put_status(:forbidden)
            |> json(%{error: "You don't have permission to access this character"})
        end
    end
  end

  def import(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id

    unless campaign_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No current campaign set"})
    else
      # Handle PDF upload
      case params["pdf_file"] do
        %Plug.Upload{} = upload ->
          campaign = ShotElixir.Campaigns.get_campaign(campaign_id)

          case ShotElixir.Services.PdfService.pdf_to_character(upload, campaign, current_user) do
            {:ok, character_attrs, weapons, schticks} ->
              # Create character with attributes from PDF
              case Characters.create_character(character_attrs) do
                {:ok, character} ->
                  # Associate weapons with character
                  if Enum.any?(weapons) do
                    now = DateTime.utc_now()

                    weapon_records =
                      Enum.map(weapons, fn weapon ->
                        %{
                          character_id: Ecto.UUID.dump!(character.id),
                          weapon_id: Ecto.UUID.dump!(weapon.id),
                          created_at: now,
                          updated_at: now
                        }
                      end)

                    ShotElixir.Repo.insert_all(
                      "character_weapons",
                      weapon_records,
                      on_conflict: :nothing
                    )
                  end

                  # Associate schticks with character
                  if Enum.any?(schticks) do
                    now = DateTime.utc_now()

                    schtick_records =
                      Enum.map(schticks, fn schtick ->
                        %{
                          character_id: Ecto.UUID.dump!(character.id),
                          schtick_id: Ecto.UUID.dump!(schtick.id),
                          created_at: now,
                          updated_at: now
                        }
                      end)

                    ShotElixir.Repo.insert_all(
                      "character_schticks",
                      schtick_records,
                      on_conflict: :nothing
                    )
                  end

                  # Reload character with associations
                  character = Characters.get_character(character.id)

                  conn
                  |> put_status(:created)
                  |> put_view(ShotElixirWeb.Api.V2.CharacterView)
                  |> render("show.json", character: character)

                {:error, %Ecto.Changeset{} = changeset} ->
                  conn
                  |> put_status(:unprocessable_entity)
                  |> put_view(ShotElixirWeb.Api.V2.CharacterView)
                  |> render("error.json", changeset: changeset)
              end

            {:error, reason} ->
              conn
              |> put_status(:unprocessable_entity)
              |> json(%{error: "PDF import failed: #{reason}"})
          end

        _ ->
          conn
          |> put_status(:bad_request)
          |> json(%{error: "No PDF file provided"})
      end
    end
  end

  def autocomplete(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)
    campaign_id = current_user.current_campaign_id || params["campaign_id"]

    unless campaign_id do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "No current campaign set"})
    else
      characters = Characters.search_characters(campaign_id, params["q"] || "")

      conn
      |> put_view(ShotElixirWeb.Api.V2.CharacterView)
      |> render("autocomplete.json", characters: characters)
    end
  end

  def remove_image(conn, %{"character_id" => id}) do
    current_user = Guardian.Plug.current_resource(conn)

    with %Character{} = character <- Characters.get_character(id),
         :ok <- authorize_character_edit(character, current_user) do
      # Remove image from ActiveStorage
      case ShotElixir.ActiveStorage.delete_image("Character", character.id) do
        {:ok, _} ->
          # Reload character to get fresh data after image removal
          updated_character = Characters.get_character(character.id)

          conn
          |> put_view(ShotElixirWeb.Api.V2.CharacterView)
          |> render("show.json", character: updated_character)

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(ShotElixirWeb.Api.V2.CharacterView)
          |> render("error.json", changeset: changeset)
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  # Authorization helpers
  defp authorize_character_access(character, user) do
    campaign_id = character.campaign_id
    campaigns = ShotElixir.Campaigns.get_user_campaigns(user.id)

    if Enum.any?(campaigns, fn c -> c.id == campaign_id end) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp authorize_character_edit(character, user) do
    campaign_id = character.campaign_id
    # Get user's campaigns (includes both owned and membership)
    user_campaigns = Campaigns.get_user_campaigns(user.id)
    is_member = Enum.any?(user_campaigns, fn c -> c.id == campaign_id end)

    # For cross-campaign security, return :not_found for non-members, :forbidden for members
    cond do
      # Character owner can always edit
      character.user_id == user.id -> :ok
      # Admin can edit any character
      user.admin -> :ok
      # Gamemaster can edit if they're a member of the character's campaign
      user.gamemaster && is_member -> :ok
      # Regular member of the campaign gets forbidden (they know character exists but can't edit)
      is_member -> {:error, :forbidden}
      # Non-members get not_found (don't reveal character exists)
      true -> {:error, :not_found}
    end
  end
end
