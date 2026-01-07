defmodule ShotElixir.Parties.PartyTemplate do
  @moduledoc """
  Hardcoded party composition templates for common encounter structures.

  Templates define role-based slots that can be applied to a party,
  allowing gamemasters to quickly set up common encounter patterns.
  """

  @templates %{
    "boss_fight" => %{
      key: "boss_fight",
      name: "Boss Fight",
      description: "A climactic encounter with a major villain and support",
      slots: [
        %{role: :boss, label: "Boss"},
        %{role: :featured_foe, label: "Lieutenant"},
        %{role: :featured_foe, label: "Lieutenant"},
        %{role: :mook, label: "Mook Squad", default_mook_count: 12}
      ]
    },
    "ambush" => %{
      key: "ambush",
      name: "Ambush",
      description: "A surprise attack with a leader and mook groups",
      slots: [
        %{role: :featured_foe, label: "Leader"},
        %{role: :mook, label: "Ambushers", default_mook_count: 8},
        %{role: :mook, label: "Backup", default_mook_count: 6}
      ]
    },
    "mixed_threat" => %{
      key: "mixed_threat",
      name: "Mixed Threat",
      description: "A balanced encounter with varied enemy types and an ally",
      slots: [
        %{role: :boss, label: "Boss"},
        %{role: :featured_foe, label: "Elite"},
        %{role: :ally, label: "Ally NPC"},
        %{role: :mook, label: "Minions", default_mook_count: 10}
      ]
    },
    "mook_horde" => %{
      key: "mook_horde",
      name: "Mook Horde",
      description: "Waves of unnamed opponents",
      slots: [
        %{role: :mook, label: "Wave 1", default_mook_count: 15},
        %{role: :mook, label: "Wave 2", default_mook_count: 15},
        %{role: :mook, label: "Wave 3", default_mook_count: 15}
      ]
    },
    "featured_foes" => %{
      key: "featured_foes",
      name: "Featured Foes",
      description: "A group of named opponents without a boss",
      slots: [
        %{role: :featured_foe, label: "Featured Foe"},
        %{role: :featured_foe, label: "Featured Foe"},
        %{role: :featured_foe, label: "Featured Foe"},
        %{role: :mook, label: "Support", default_mook_count: 6}
      ]
    },
    "uber_boss" => %{
      key: "uber_boss",
      name: "Uber-Boss Showdown",
      description: "A major villain with significant support",
      slots: [
        %{role: :boss, label: "Uber-Boss"},
        %{role: :featured_foe, label: "Right Hand"},
        %{role: :featured_foe, label: "Bodyguard"},
        %{role: :featured_foe, label: "Bodyguard"},
        %{role: :mook, label: "Elite Guards", default_mook_count: 20}
      ]
    },
    "escort" => %{
      key: "escort",
      name: "Escort Mission",
      description: "Protecting an ally from attackers",
      slots: [
        %{role: :ally, label: "VIP to Protect"},
        %{role: :featured_foe, label: "Attacker Leader"},
        %{role: :mook, label: "Attackers", default_mook_count: 12}
      ]
    },
    "simple_encounter" => %{
      key: "simple_encounter",
      name: "Simple Encounter",
      description: "A basic encounter with a featured foe and mooks",
      slots: [
        %{role: :featured_foe, label: "Featured Foe"},
        %{role: :mook, label: "Mooks", default_mook_count: 8}
      ]
    }
  }

  @doc """
  Returns all available party templates.
  """
  def list_templates do
    @templates
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Gets a specific template by key.

  Returns `{:ok, template}` if found, `{:error, :not_found}` otherwise.
  """
  def get_template(key) when is_binary(key) do
    case Map.get(@templates, key) do
      nil -> {:error, :not_found}
      template -> {:ok, template}
    end
  end

  def get_template(_), do: {:error, :invalid_key}

  @doc """
  Gets a template by key, raising if not found.
  """
  def get_template!(key) do
    case get_template(key) do
      {:ok, template} -> template
      {:error, :not_found} -> raise "Template not found: #{key}"
      {:error, :invalid_key} -> raise "Invalid template key"
    end
  end

  @doc """
  Returns the list of valid template keys.
  """
  def template_keys do
    Map.keys(@templates)
  end

  @doc """
  Checks if a template key is valid.
  """
  def valid_template?(key) when is_binary(key) do
    Map.has_key?(@templates, key)
  end

  def valid_template?(_), do: false
end
