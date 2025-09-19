defmodule ShotElixirWeb.Api.V2.SiteViewTest do
  use ExUnit.Case, async: true

  alias ShotElixirWeb.Api.V2.SiteView

  describe "render/2" do
    test "converts binary UUIDs to strings in index payload" do
      uuid = Ecto.UUID.generate()
      {:ok, binary_uuid} = Ecto.UUID.dump(uuid)

      data = %{
        sites: [
          %{
            id: binary_uuid,
            name: "Lion Rock",
            description: nil,
            faction_id: binary_uuid,
            juncture_id: nil,
            created_at: "2024-01-01T00:00:00Z",
            updated_at: "2024-01-01T00:00:00Z",
            active: true
          }
        ],
        factions: [
          %{id: binary_uuid, name: "Four Dragons"}
        ],
        meta: %{current_page: 1, per_page: 5, total_count: 1, total_pages: 1},
        is_autocomplete: false
      }

      rendered = SiteView.render("index.json", %{sites: data})

      assert Jason.encode!(rendered)
      assert rendered.sites |> hd() |> Map.fetch!(:id) == uuid
      assert rendered.factions |> hd() |> Map.fetch!(:id) == uuid
      assert rendered.meta == %{current_page: 1, per_page: 5, total_count: 1, total_pages: 1}
    end
  end
end
