defmodule ShotElixirWeb.Api.V2.SiteViewSmokeTest do
  use ExUnit.Case, async: true

  alias ShotElixirWeb.Api.V2.SiteView

  test "show.json turns binary UUID into string" do
    uuid = Ecto.UUID.generate()
    {:ok, raw_uuid} = Ecto.UUID.dump(uuid)

    site = %{
      id: raw_uuid,
      name: "Test",
      description: nil,
      faction_id: nil,
      juncture_id: nil,
      created_at: ~U[2024-01-01 00:00:00Z],
      updated_at: ~U[2024-01-01 00:00:00Z],
      active: true,
      campaign_id: raw_uuid,
      faction: nil,
      juncture: nil,
      attunements: []
    }

    payload = SiteView.render("show.json", %{site: site})

    assert payload[:site][:id] == uuid
  end
end
