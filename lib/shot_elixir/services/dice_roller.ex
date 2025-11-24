defmodule ShotElixir.Services.DiceRoller do
  @moduledoc """
  Dice rolling service for Feng Shui 2 RPG.
  Supports basic die rolls, exploding dice, and swerves.
  """
  alias ShotElixir.Repo
  alias ShotElixir.Discord.Swerve
  import Ecto.Query

  @doc """
  Roll a single six-sided die.
  """
  def die_roll do
    :rand.uniform(6)
  end

  @doc """
  Roll an exploding die (rolls again on 6).
  Returns a map with :sum and :rolls keys.
  """
  def exploding_die_roll do
    rolls = do_exploding_roll([])
    %{sum: Enum.sum(rolls), rolls: rolls}
  end

  defp do_exploding_roll(acc) do
    roll = die_roll()
    new_acc = [roll | acc]

    if roll == 6 do
      do_exploding_roll(new_acc)
    else
      Enum.reverse(new_acc)
    end
  end

  @doc """
  Roll a swerve: positive exploding die minus negative exploding die.
  Returns a map with positives, negatives, total, boxcars, and rolled_at.
  """
  def swerve do
    positives = exploding_die_roll()
    negatives = exploding_die_roll()
    boxcars = List.first(positives.rolls) == 6 && List.first(negatives.rolls) == 6

    %{
      positives: positives,
      negatives: negatives,
      total: positives.sum - negatives.sum,
      boxcars: boxcars,
      rolled_at: DateTime.utc_now()
    }
  end

  @doc """
  Format a swerve for Discord display.
  """
  def discord_format(swerve, _username) do
    message = []
    message = ["# #{swerve.total}" | message]

    message =
      if swerve.boxcars do
        ["BOXCARS!" | message]
      else
        message
      end

    positive_rolls = Enum.join(swerve.positives.rolls, ", ")
    negative_rolls = Enum.join(swerve.negatives.rolls, ", ")

    message = ["```diff" | message]
    message = ["+ #{swerve.positives.sum} (#{positive_rolls})" | message]
    message = ["- #{swerve.negatives.sum} (#{negative_rolls})" | message]
    message = ["```" | message]

    message
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  @doc """
  Save a swerve to the database for a user.
  """
  def save_swerve(swerve, username) do
    attrs = %{
      username: username,
      positives_sum: swerve.positives.sum,
      positives_rolls: swerve.positives.rolls,
      negatives_sum: swerve.negatives.sum,
      negatives_rolls: swerve.negatives.rolls,
      total: swerve.total,
      boxcars: swerve.boxcars,
      rolled_at: swerve.rolled_at
    }

    %Swerve{}
    |> Swerve.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Load all swerves for a user from the database.
  """
  def load_swerves(username) do
    Swerve
    |> where([s], s.username == ^username)
    |> order_by([s], desc: s.rolled_at)
    |> Repo.all()
    |> Enum.map(fn swerve ->
      %{
        positives: %{sum: swerve.positives_sum, rolls: swerve.positives_rolls},
        negatives: %{sum: swerve.negatives_sum, rolls: swerve.negatives_rolls},
        total: swerve.total,
        boxcars: swerve.boxcars,
        rolled_at: swerve.rolled_at
      }
    end)
  end

  @doc """
  Clear all swerves for a user.
  """
  def clear_swerves(username) do
    Swerve
    |> where([s], s.username == ^username)
    |> Repo.delete_all()
  end
end
