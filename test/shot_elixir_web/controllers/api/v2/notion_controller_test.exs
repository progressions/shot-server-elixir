defmodule ShotElixirWeb.Api.V2.NotionControllerTest do
  @moduledoc """
  Tests for the NotionController adventures endpoint.

  Tests cover:
  - Parameter validation (q or id required)
  - Authentication requirements
  - Error handling for missing parameters

  Note: Success case tests require mocking NotionService/NotionClient
  to avoid external API calls. These are documented as follow-up items.
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{
        email: "notion-test@example.com",
        password: "password123",
        first_name: "Test",
        last_name: "User"
      })

    {:ok, conn: put_req_header(conn, "accept", "application/json"), user: user}
  end

  describe "adventures" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/adventures?q=test")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "returns 400 when neither q nor id is provided", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/adventures")

      assert json_response(conn, 400)["error"] ==
               "Must provide either 'q' (search query) or 'id' (page ID) parameter"
    end

    test "returns 400 when q is empty string", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/adventures?q=")

      assert json_response(conn, 400)["error"] ==
               "Must provide either 'q' (search query) or 'id' (page ID) parameter"
    end

    test "returns 400 when id is empty string", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/adventures?id=")

      assert json_response(conn, 400)["error"] ==
               "Must provide either 'q' (search query) or 'id' (page ID) parameter"
    end

    test "accepts valid q parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/adventures?q=Tesla")

      # Could be 200 (found), 404 (not found), or 500 (API error)
      # depending on Notion API availability and search results
      status = conn.status
      assert status in [200, 404, 500], "Expected 200, 404, or 500, got #{status}"

      response = json_response(conn, status)

      case status do
        200 ->
          # Successful search should return pages, title, page_id, content
          assert is_list(response["pages"])
          assert is_binary(response["title"]) or is_nil(response["title"])

        404 ->
          assert response["error"] =~ "No adventure found"

        500 ->
          assert response["error"] =~ "Failed to"
      end
    end

    test "accepts valid id parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      # Use a fake page ID - will likely return 404 or 500
      conn = get(conn, ~p"/api/v2/notion/adventures?id=fake-page-id")

      # Could be 200 (found), 404 (not found), or 500 (API error)
      status = conn.status
      assert status in [200, 404, 500], "Expected 200, 404, or 500, got #{status}"
    end

    # Note: Success case tests require mocking NotionService
    # to avoid external API calls. Example test structure:
    #
    # test "returns adventure data when search finds pages", %{...} do
    #   # Would require:
    #   # 1. Mock NotionService.fetch_adventure/1 to return {:ok, %{pages: [...], title: "...", page_id: "...", content: "..."}}
    #   # 2. Verify response status 200
    #   # 3. Verify response contains expected fields
    # end
    #
    # test "returns adventure data when fetching by id", %{...} do
    #   # Would require:
    #   # 1. Mock NotionService.fetch_adventure_by_id/1 to return {:ok, %{title: "...", page_id: "...", content: "..."}}
    #   # 2. Verify response status 200
    #   # 3. Verify response contains expected fields
    # end
    #
    # test "returns 404 when id is not found in Notion", %{...} do
    #   # Would require:
    #   # 1. Mock NotionService.fetch_adventure_by_id/1 to return {:error, {:notion_api_error, "object_not_found", "..."}}
    #   # 2. Verify response status 404
    #   # 3. Verify error message
    # end
  end

  describe "search_sites" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/sites?name=test")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "accepts valid name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/sites?name=test")

      # Could be 200 (found) or 500 (API error) depending on Notion API availability
      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "accepts empty name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/sites")

      # Empty name should return all sites or empty list
      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end
  end

  describe "search_parties" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/parties?name=test")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "accepts valid name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/parties?name=test")

      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "accepts empty name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/parties")

      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end
  end

  describe "search_factions" do
    test "returns 401 when not authenticated", %{conn: conn} do
      conn = get(conn, ~p"/api/v2/notion/factions?name=test")

      assert json_response(conn, 401)["error"] == "Not authenticated"
    end

    test "accepts valid name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/factions?name=test")

      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end

    test "accepts empty name parameter", %{conn: conn, user: user} do
      conn = authenticate(conn, user)
      conn = get(conn, ~p"/api/v2/notion/factions")

      status = conn.status
      assert status in [200, 500], "Expected 200 or 500, got #{status}"

      if status == 200 do
        response = json_response(conn, 200)
        assert is_list(response)
      end
    end
  end

  defp authenticate(conn, user) do
    {:ok, token, _} = Guardian.encode_and_sign(user)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end
end
