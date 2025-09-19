defmodule ShotElixir.ImagePositions do
  @moduledoc """
  Context for working with image positioning overlays.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.ImagePositions.ImagePosition

  def list_for(positionable_type, positionable_id) do
    ImagePosition
    |> where(
      [ip],
      ip.positionable_type == ^positionable_type and ip.positionable_id == ^positionable_id
    )
    |> Repo.all()
  end

  def create(attrs) do
    %ImagePosition{}
    |> ImagePosition.changeset(attrs)
    |> Repo.insert()
  end

  def upsert(positionable_type, positionable_id, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put("positionable_type", positionable_type)
      |> Map.put("positionable_id", positionable_id)

    context = Map.get(attrs, "context") || Map.get(attrs, :context)

    case get_by_positionable_and_context(positionable_type, positionable_id, context) do
      nil ->
        create(attrs)

      %ImagePosition{} = image_position ->
        image_position
        |> ImagePosition.changeset(attrs)
        |> Repo.update()
    end
  end

  defp get_by_positionable_and_context(_positionable_type, _positionable_id, nil), do: nil

  defp get_by_positionable_and_context(positionable_type, positionable_id, context) do
    Repo.get_by(ImagePosition,
      positionable_type: positionable_type,
      positionable_id: positionable_id,
      context: context
    )
  end
end
