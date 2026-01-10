defmodule ShotElixirWeb.Api.V2.DiceController do
  use ShotElixirWeb, :controller

  alias ShotElixir.Services.DiceRoller

  action_fallback ShotElixirWeb.FallbackController

  @doc """
  POST /api/v2/dice/swerve
  Roll a swerve (positive exploding die minus negative exploding die).
  Returns the swerve result with positives, negatives, total, and boxcars flag.
  """
  def swerve(conn, _params) do
    swerve_result = DiceRoller.swerve()

    conn
    |> put_status(:ok)
    |> json(%{
      positives: %{
        sum: swerve_result.positives.sum,
        rolls: swerve_result.positives.rolls
      },
      negatives: %{
        sum: swerve_result.negatives.sum,
        rolls: swerve_result.negatives.rolls
      },
      total: swerve_result.total,
      boxcars: swerve_result.boxcars
    })
  end

  @doc """
  POST /api/v2/dice/roll
  Roll a single six-sided die.
  """
  def roll(conn, _params) do
    result = DiceRoller.die_roll()

    conn
    |> put_status(:ok)
    |> json(%{result: result})
  end

  @doc """
  POST /api/v2/dice/exploding
  Roll an exploding die (reroll on 6).
  """
  def exploding(conn, _params) do
    result = DiceRoller.exploding_die_roll()

    conn
    |> put_status(:ok)
    |> json(%{
      sum: result.sum,
      rolls: result.rolls
    })
  end
end
