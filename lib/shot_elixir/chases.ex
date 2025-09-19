defmodule ShotElixir.Chases do
  @moduledoc """
  Domain logic for chase relationships.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Chases.ChaseRelationship
  alias ShotElixir.Fights
  alias ShotElixir.Vehicles

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

  defp maybe_preload_related(nil), do: nil

  defp maybe_preload_related(relationship) do
    Repo.preload(relationship, [:pursuer, :evader])
  end

  defp ensure_campaign_resources(attrs, campaign_id) do
    attrs = Map.new(attrs)

    with {:ok, fight_id} <- require_uuid(attrs, "fight_id"),
         {:ok, pursuer_id} <- require_uuid(attrs, "pursuer_id"),
         {:ok, evader_id} <- require_uuid(attrs, "evader_id"),
         {:ok, _fight} <- verify_fight(fight_id, campaign_id),
         {:ok, _pursuer} <- verify_vehicle(pursuer_id, campaign_id),
         {:ok, _evader} <- verify_vehicle(evader_id, campaign_id) do
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

  defp verify_vehicle(id, campaign_id) do
    case Vehicles.get_vehicle(id) do
      nil -> {:error, :invalid_resource}
      vehicle when vehicle.campaign_id == campaign_id -> {:ok, vehicle}
      _ -> {:error, :invalid_resource}
    end
  end

  defp maybe_filter_by_fight(query, %{"fight_id" => fight_id}) when fight_id not in [nil, ""] do
    where(query, [cr, _f], cr.fight_id == ^fight_id)
  end

  defp maybe_filter_by_fight(query, _), do: query

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
