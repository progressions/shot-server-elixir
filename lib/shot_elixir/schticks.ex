defmodule ShotElixir.Schticks do
  @moduledoc """
  The Schticks context for managing character abilities.
  """

  import Ecto.Query, warn: false
  alias ShotElixir.Repo
  alias ShotElixir.Schticks.Schtick

  def list_schticks(campaign_id, filters \\ %{}) do
    query = from s in Schtick,
      where: s.campaign_id == ^campaign_id and s.active == true,
      order_by: [asc: s.category, asc: fragment("lower(?)", s.name)]

    query = apply_filters(query, filters)

    query
    |> preload_prerequisites()
    |> Repo.all()
  end

  defp apply_filters(query, filters) do
    query
    |> filter_by_category(filters["category"])
    |> filter_by_path(filters["path"])
  end

  defp filter_by_category(query, nil), do: query
  defp filter_by_category(query, category) do
    from s in query, where: s.category == ^category
  end

  defp filter_by_path(query, nil), do: query
  defp filter_by_path(query, path) do
    from s in query, where: s.path == ^path
  end

  defp preload_prerequisites(query) do
    from s in query,
      left_join: p in Schtick,
      on: s.prerequisite_id == p.id,
      preload: [prerequisite: p]
  end

  def get_schtick!(id) do
    Schtick
    |> preload(:prerequisite)
    |> Repo.get!(id)
  end

  def get_schtick(id) do
    Schtick
    |> preload(:prerequisite)
    |> Repo.get(id)
  end

  def create_schtick(attrs \\ %{}) do
    %Schtick{}
    |> Schtick.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, schtick} -> {:ok, Repo.preload(schtick, :prerequisite)}
      error -> error
    end
  end

  def update_schtick(%Schtick{} = schtick, attrs) do
    schtick
    |> Schtick.changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, schtick} -> {:ok, Repo.preload(schtick, :prerequisite)}
      error -> error
    end
  end

  def delete_schtick(%Schtick{} = schtick) do
    # Check if any schticks depend on this one as a prerequisite
    dependent_count = from(s in Schtick,
      where: s.prerequisite_id == ^schtick.id and s.active == true,
      select: count(s.id))
    |> Repo.one()

    if dependent_count > 0 do
      {:error, :has_dependents}
    else
      schtick
      |> Ecto.Changeset.change(active: false)
      |> Repo.update()
    end
  end

  def get_prerequisite_tree(schtick_id) do
    with schtick when not is_nil(schtick) <- get_schtick(schtick_id) do
      build_tree(schtick)
    else
      nil -> {:error, :not_found}
    end
  end

  defp build_tree(nil), do: nil
  defp build_tree(schtick) do
    %{
      id: schtick.id,
      name: schtick.name,
      category: schtick.category,
      prerequisite: build_tree(schtick.prerequisite)
    }
  end

  def categories, do: Schtick.categories()
  def paths, do: Schtick.paths()
end