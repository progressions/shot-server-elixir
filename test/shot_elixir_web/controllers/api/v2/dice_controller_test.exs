defmodule ShotElixirWeb.Api.V2.DiceControllerTest do
  @moduledoc """
  Tests for the Dice Controller endpoints.

  Tests cover:
  - Swerve endpoint returns correct structure with positives, negatives, total, and boxcars
  - Roll endpoint returns a number between 1 and 6
  - Exploding endpoint returns structure with sum and rolls
  """
  use ShotElixirWeb.ConnCase, async: true

  alias ShotElixir.Accounts
  alias ShotElixir.Guardian

  setup %{conn: conn} do
    {:ok, user} =
      Accounts.create_user(%{
        email: "player@example.com",
        password: "password123",
        first_name: "Player",
        last_name: "One",
        gamemaster: false
      })

    {:ok, token, _claims} = Guardian.encode_and_sign(user)

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token}")

    {:ok, conn: conn, user: user}
  end

  describe "POST /api/v2/dice/swerve" do
    test "returns swerve result with expected structure", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/dice/swerve")
      response = json_response(conn, 200)

      # Verify structure
      assert Map.has_key?(response, "positives")
      assert Map.has_key?(response, "negatives")
      assert Map.has_key?(response, "total")
      assert Map.has_key?(response, "boxcars")

      # Verify positives structure
      assert Map.has_key?(response["positives"], "sum")
      assert Map.has_key?(response["positives"], "rolls")
      assert is_integer(response["positives"]["sum"])
      assert is_list(response["positives"]["rolls"])
      assert response["positives"]["sum"] >= 1

      # Verify negatives structure
      assert Map.has_key?(response["negatives"], "sum")
      assert Map.has_key?(response["negatives"], "rolls")
      assert is_integer(response["negatives"]["sum"])
      assert is_list(response["negatives"]["rolls"])
      assert response["negatives"]["sum"] >= 1

      # Verify total is correct calculation
      expected_total = response["positives"]["sum"] - response["negatives"]["sum"]
      assert response["total"] == expected_total

      # Verify boxcars is boolean
      assert is_boolean(response["boxcars"])
    end

    test "rolls are all between 1 and 6", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/dice/swerve")
      response = json_response(conn, 200)

      for roll <- response["positives"]["rolls"] do
        assert roll >= 1 and roll <= 6
      end

      for roll <- response["negatives"]["rolls"] do
        assert roll >= 1 and roll <= 6
      end
    end
  end

  describe "POST /api/v2/dice/roll" do
    test "returns a single die result between 1 and 6", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/dice/roll")
      response = json_response(conn, 200)

      assert Map.has_key?(response, "result")
      assert is_integer(response["result"])
      assert response["result"] >= 1 and response["result"] <= 6
    end

    test "multiple rolls return values in valid range", %{conn: conn} do
      # Roll multiple times to increase confidence
      results =
        for _i <- 1..20 do
          conn = post(conn, ~p"/api/v2/dice/roll")
          json_response(conn, 200)["result"]
        end

      for result <- results do
        assert result >= 1 and result <= 6
      end
    end
  end

  describe "POST /api/v2/dice/exploding" do
    test "returns exploding die result with expected structure", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/dice/exploding")
      response = json_response(conn, 200)

      assert Map.has_key?(response, "sum")
      assert Map.has_key?(response, "rolls")
      assert is_integer(response["sum"])
      assert is_list(response["rolls"])
      assert response["sum"] >= 1
      assert length(response["rolls"]) >= 1
    end

    test "sum equals total of rolls", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/dice/exploding")
      response = json_response(conn, 200)

      expected_sum = Enum.sum(response["rolls"])
      assert response["sum"] == expected_sum
    end

    test "all rolls are between 1 and 6", %{conn: conn} do
      conn = post(conn, ~p"/api/v2/dice/exploding")
      response = json_response(conn, 200)

      for roll <- response["rolls"] do
        assert roll >= 1 and roll <= 6
      end
    end

    test "last roll is not 6 (explosion stops)", %{conn: conn} do
      # Run multiple times to verify explosion logic
      for _i <- 1..10 do
        conn = post(conn, ~p"/api/v2/dice/exploding")
        response = json_response(conn, 200)

        # Last roll should not be 6 (otherwise it would have exploded again)
        last_roll = List.last(response["rolls"])
        assert last_roll != 6
      end
    end
  end
end
