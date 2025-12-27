defmodule ShotElixir.Chases do
  @moduledoc """
  Domain logic for chase relationships.

  Chase relationships use shot IDs (vehicle instances in a fight) rather than
  vehicle template IDs. This allows multiple instances of the same vehicle
  to participate in different chase relationships.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Chases.ChaseRelationship
  alias ShotElixir.Fights
  alias ShotElixir.Fights.Shot

  def list_relationships(campaign_id, params \\ %{}) do
    ChaseRelationship
    |> join(:inner, [cr], f in assoc(cr, :fight))
    |> where([cr, f], f.campaign_id == ^campaign_id)
    |> maybe_filter_by_fight(params)
    |> maybe_filter_by_vehicle(params)
    |> maybe_filter_by_active(params)
    |> Repo.all()
  end

  def get_relationship(id, campaign_id) do
    ChaseRelationship
    |> join(:inner, [cr], f in assoc(cr, :fight))
    |> where([cr, f], f.campaign_id == ^campaign_id and cr.id == ^id)
    |> select([cr, _f], cr)
    |> Repo.one()
    |> maybe_preload_related()
  end

  def create_relationship(attrs, campaign_id) do
    with {:ok, normalized_attrs} <- ensure_campaign_resources(attrs, campaign_id) do
      %ChaseRelationship{}
      |> ChaseRelationship.changeset(normalized_attrs)
      |> Repo.insert()
    end
  end

  def update_relationship(%ChaseRelationship{} = relationship, attrs) do
    relationship
    |> ChaseRelationship.update_changeset(attrs)
    |> Repo.update()
  end

  def deactivate_relationship(%ChaseRelationship{} = relationship) do
    update_relationship(relationship, %{active: false})
  end

  @doc """
  Gets or creates a chase relationship between a pursuer and evader in a fight.
  Uses shot IDs (vehicle instances) not vehicle template IDs.
  """
  def get_or_create_relationship(fight_id, pursuer_shot_id, evader_shot_id) do
    case get_relationship_by_shots(fight_id, pursuer_shot_id, evader_shot_id) do
      nil ->
        %ChaseRelationship{}
        |> ChaseRelationship.changeset(%{
          "fight_id" => fight_id,
          "pursuer_id" => pursuer_shot_id,
          "evader_id" => evader_shot_id,
          "position" => "far"
        })
        |> Repo.insert()

      relationship ->
        {:ok, relationship}
    end
  end

  @doc """
  Gets a chase relationship by pursuer and evader shot IDs (vehicle instances).
  """
  def get_relationship_by_shots(fight_id, pursuer_shot_id, evader_shot_id) do
    ChaseRelationship
    |> where(
      [cr],
      cr.fight_id == ^fight_id and cr.pursuer_id == ^pursuer_shot_id and
        cr.evader_id == ^evader_shot_id and cr.active == true
    )
    |> Repo.one()
  end

  defp maybe_preload_related(nil), do: nil

  defp maybe_preload_related(relationship) do
    Repo.preload(relationship, [:pursuer, :evader])
  end

  defp ensure_campaign_resources(attrs, campaign_id) do
    attrs = Map.new(attrs)

    with {:ok, fight_id} <- require_uuid(attrs, "fight_id"),
         {:ok, pursuer_id} <- require_uuid(attrs, "pursuer_id"),
         {:ok, evader_id} <- require_uuid(attrs, "evader_id"),
         {:ok, fight} <- verify_fight(fight_id, campaign_id),
         {:ok, _pursuer} <- verify_shot(pursuer_id, fight),
         {:ok, _evader} <- verify_shot(evader_id, fight) do
      {:ok,
       attrs
       |> Map.put("fight_id", fight_id)
       |> Map.put("pursuer_id", pursuer_id)
       |> Map.put("evader_id", evader_id)}
    else
      {:error, _} = err -> err
      :error -> {:error, :invalid_attributes}
    end
  end

  defp require_uuid(attrs, key) do
    case Map.get(attrs, key) do
      nil -> {:error, :invalid_resource}
      value -> {:ok, value}
    end
  end

  defp verify_fight(id, campaign_id) do
    case Fights.get_fight(id) do
      nil -> {:error, :invalid_resource}
      fight when fight.campaign_id == campaign_id -> {:ok, fight}
      _ -> {:error, :invalid_resource}
    end
  end

  defp verify_shot(id, fight) do
    case Repo.get(Shot, id) do
      nil -> {:error, :invalid_resource}
      shot when shot.fight_id == fight.id -> {:ok, shot}
      _ -> {:error, :invalid_resource}
    end
  end

  defp maybe_filter_by_fight(query, %{"fight_id" => fight_id}) when fight_id not in [nil, ""] do
    where(query, [cr, _f], cr.fight_id == ^fight_id)
  end

  defp maybe_filter_by_fight(query, _), do: query

  defp maybe_filter_by_vehicle(query, %{"shot_id" => shot_id})
       when shot_id not in [nil, ""] do
    where(query, [cr, _f], cr.pursuer_id == ^shot_id or cr.evader_id == ^shot_id)
  end

  # Also support legacy vehicle_id parameter for backwards compatibility
  defp maybe_filter_by_vehicle(query, %{"vehicle_id" => vehicle_id})
       when vehicle_id not in [nil, ""] do
    where(query, [cr, _f], cr.pursuer_id == ^vehicle_id or cr.evader_id == ^vehicle_id)
  end

  defp maybe_filter_by_vehicle(query, _), do: query

  defp maybe_filter_by_active(query, %{"active" => active}) when active not in [nil, ""] do
    case parse_boolean(active) do
      nil -> query
      value -> where(query, [cr, _f], cr.active == ^value)
    end
  end

  defp maybe_filter_by_active(query, _), do: where(query, [cr, _f], cr.active == true)

  defp parse_boolean(value) when is_boolean(value), do: value

  defp parse_boolean(value) when is_binary(value) do
    case String.downcase(value) do
      "true" -> true
      "false" -> false
      _ -> nil
    end
  end

  defp parse_boolean(_), do: nil
end
