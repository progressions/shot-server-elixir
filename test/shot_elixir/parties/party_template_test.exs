defmodule ShotElixir.Parties.PartyTemplateTest do
  use ExUnit.Case, async: true
  alias ShotElixir.Parties.PartyTemplate

  describe "list_templates/0" do
    test "returns all templates sorted by name" do
      templates = PartyTemplate.list_templates()

      assert is_list(templates)
      assert length(templates) == 8

      # Verify sorted by name
      names = Enum.map(templates, & &1.name)
      assert names == Enum.sort(names)
    end

    test "each template has required fields" do
      templates = PartyTemplate.list_templates()

      for template <- templates do
        assert is_binary(template.key)
        assert is_binary(template.name)
        assert is_binary(template.description)
        assert is_list(template.slots)
        assert length(template.slots) > 0
      end
    end

    test "each slot has required fields" do
      templates = PartyTemplate.list_templates()

      for template <- templates do
        for slot <- template.slots do
          assert Map.has_key?(slot, :role)
          assert Map.has_key?(slot, :label)
          assert slot.role in [:boss, :featured_foe, :mook, :ally]

          # Mook slots should have default_mook_count
          if slot.role == :mook do
            assert Map.has_key?(slot, :default_mook_count)
            assert is_integer(slot.default_mook_count)
            assert slot.default_mook_count > 0
          end
        end
      end
    end
  end

  describe "get_template/1" do
    test "returns template for valid key" do
      assert {:ok, template} = PartyTemplate.get_template("boss_fight")
      assert template.key == "boss_fight"
      assert template.name == "Boss Fight"
      assert is_list(template.slots)
    end

    test "returns error for invalid key" do
      assert {:error, :not_found} = PartyTemplate.get_template("nonexistent")
    end

    test "returns error for non-string key" do
      assert {:error, :invalid_key} = PartyTemplate.get_template(123)
      assert {:error, :invalid_key} = PartyTemplate.get_template(nil)
      assert {:error, :invalid_key} = PartyTemplate.get_template(:atom)
    end

    test "returns all expected templates" do
      expected_keys = [
        "boss_fight",
        "ambush",
        "mixed_threat",
        "mook_horde",
        "featured_foes",
        "uber_boss",
        "escort",
        "simple_encounter"
      ]

      for key <- expected_keys do
        assert {:ok, template} = PartyTemplate.get_template(key)
        assert template.key == key
      end
    end
  end

  describe "get_template!/1" do
    test "returns template for valid key" do
      template = PartyTemplate.get_template!("ambush")
      assert template.key == "ambush"
      assert template.name == "Ambush"
    end

    test "raises for invalid key" do
      assert_raise RuntimeError, "Template not found: nonexistent", fn ->
        PartyTemplate.get_template!("nonexistent")
      end
    end

    test "raises for non-string key" do
      assert_raise RuntimeError, "Invalid template key", fn ->
        PartyTemplate.get_template!(123)
      end
    end
  end

  describe "template_keys/0" do
    test "returns all template keys" do
      keys = PartyTemplate.template_keys()

      assert is_list(keys)
      assert length(keys) == 8
      assert "boss_fight" in keys
      assert "ambush" in keys
      assert "mook_horde" in keys
    end
  end

  describe "valid_template?/1" do
    test "returns true for valid keys" do
      assert PartyTemplate.valid_template?("boss_fight") == true
      assert PartyTemplate.valid_template?("ambush") == true
      assert PartyTemplate.valid_template?("mook_horde") == true
    end

    test "returns false for invalid keys" do
      assert PartyTemplate.valid_template?("nonexistent") == false
      assert PartyTemplate.valid_template?("") == false
    end

    test "returns false for non-string values" do
      assert PartyTemplate.valid_template?(nil) == false
      assert PartyTemplate.valid_template?(123) == false
      assert PartyTemplate.valid_template?(:atom) == false
    end
  end

  describe "specific template structures" do
    test "boss_fight has correct structure" do
      {:ok, template} = PartyTemplate.get_template("boss_fight")

      assert template.name == "Boss Fight"
      assert length(template.slots) == 4

      roles = Enum.map(template.slots, & &1.role)
      assert :boss in roles
      assert :featured_foe in roles
      assert :mook in roles
    end

    test "mook_horde has only mook slots" do
      {:ok, template} = PartyTemplate.get_template("mook_horde")

      for slot <- template.slots do
        assert slot.role == :mook
        assert is_integer(slot.default_mook_count)
      end
    end

    test "escort has ally slot" do
      {:ok, template} = PartyTemplate.get_template("escort")

      roles = Enum.map(template.slots, & &1.role)
      assert :ally in roles
    end
  end
end
