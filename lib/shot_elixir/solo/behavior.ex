defmodule ShotElixir.Solo.Behavior do
  @moduledoc """
  Behaviour definition for solo play NPC decision-making.

  Implementations:
  - SimpleBehavior: Basic automation (attack highest-shot PC)
  - AiBehavior: LLM-powered decisions with narrative generation
  """

  alias ShotElixir.Characters.Character
  alias ShotElixir.Fights.{Fight, Shot}

  @type action_type :: :attack | :defend | :stunt
  @type behavior_type :: :simple | :ai

  @type context :: %{
          fight: Fight.t(),
          acting_character: Character.t(),
          acting_shot: Shot.t(),
          pc_shots: [Shot.t()],
          npc_shots: [Shot.t()],
          fight_history: [map()]
        }

  @type action_result :: %{
          action_type: action_type(),
          target_id: binary() | nil,
          narrative: String.t() | nil,
          dice_result: map() | nil,
          damage: integer() | nil,
          outcome: integer() | nil
        }

  @doc """
  Determine what action the NPC should take.
  Returns {:ok, action_result} or {:error, reason}.
  """
  @callback determine_action(context()) :: {:ok, action_result()} | {:error, term()}

  @doc """
  Returns the behavior type (:simple or :ai).
  """
  @callback behavior_type() :: behavior_type()

  @doc """
  Build context for behavior providers from fight state.
  """
  def build_context(fight, acting_shot, pc_character_ids) do
    # Separate PC and NPC shots
    {pc_shots, npc_shots} =
      Enum.split_with(fight.shots, fn shot ->
        shot.character_id in pc_character_ids
      end)

    # Get recent fight history (last 10 events)
    fight_history =
      case Map.get(fight, :fight_events) do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        events -> events |> Enum.take(10)
      end

    %{
      fight: fight,
      acting_character: acting_shot.character,
      acting_shot: acting_shot,
      pc_shots: pc_shots,
      npc_shots: npc_shots,
      fight_history: fight_history
    }
  end
end
