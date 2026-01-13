defmodule ShotElixir.Characters.CharacterNotionTest do
  use ShotElixir.DataCase, async: true

  alias ShotElixir.Characters.Character

  describe "attributes_from_notion/2" do
    test "sets at_a_glance when checkbox is present" do
      character = %Character{action_values: %{}, description: %{}}

      page = %{
        "id" => "page-123",
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Test Character"}]},
          "At a Glance" => %{"checkbox" => true}
        }
      }

      attrs = Character.attributes_from_notion(character, page)

      assert attrs[:at_a_glance] == true
    end

    test "does not set at_a_glance when checkbox is missing" do
      character = %Character{action_values: %{}, description: %{}}

      page = %{
        "id" => "page-456",
        "properties" => %{
          "Name" => %{"title" => [%{"plain_text" => "Test Character"}]}
        }
      }

      attrs = Character.attributes_from_notion(character, page)

      refute Map.has_key?(attrs, :at_a_glance)
    end
  end

  describe "maybe_put_at_a_glance/2" do
    test "adds at_a_glance when value is boolean" do
      attrs = %{name: "Test"}

      assert Character.maybe_put_at_a_glance(attrs, false) == %{
               name: "Test",
               at_a_glance: false
             }
    end

    test "leaves attrs unchanged when value is nil" do
      attrs = %{name: "Test"}

      assert Character.maybe_put_at_a_glance(attrs, nil) == attrs
    end
  end
end
