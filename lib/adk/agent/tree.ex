defmodule ADK.Agent.Tree do
  @moduledoc """
  Utilities for working with agent trees (hierarchies of agents and sub-agents).
  """

  @doc """
  Finds an agent by name using depth-first search.

  Returns `{:ok, agent}` if found, `:error` otherwise.
  """
  @spec find_agent(struct(), String.t()) :: {:ok, struct()} | :error
  def find_agent(agent, target_name) do
    if agent_name(agent) == target_name do
      {:ok, agent}
    else
      find_in_children(get_sub_agents(agent), target_name)
    end
  end

  defp find_in_children([], _target_name), do: :error

  defp find_in_children([child | rest], target_name) do
    case find_agent(child, target_name) do
      {:ok, _} = found -> found
      :error -> find_in_children(rest, target_name)
    end
  end

  @doc """
  Builds a map from child agent name to parent agent.
  """
  @spec build_parent_map(struct()) :: %{String.t() => struct()}
  def build_parent_map(root) do
    build_parent_map_acc(root, %{})
  end

  defp build_parent_map_acc(agent, acc) do
    agent
    |> get_sub_agents()
    |> Enum.reduce(acc, fn child, map ->
      updated = Map.put(map, agent_name(child), agent)
      build_parent_map_acc(child, updated)
    end)
  end

  @doc """
  Validates that all agent names in the tree are unique.

  Returns `{:ok, names}` where `names` is the set of all names,
  or `{:error, reason}` if duplicates are found.
  """
  @spec validate_unique_names(struct()) :: {:ok, MapSet.t()} | {:error, String.t()}
  def validate_unique_names(root) do
    case collect_names(root, %{}) do
      {:ok, map} -> {:ok, MapSet.new(Map.keys(map))}
      {:error, _} = err -> err
    end
  end

  defp collect_names(agent, seen) do
    name = agent_name(agent)

    if Map.has_key?(seen, name) do
      {:error, "duplicate agent name: #{name}"}
    else
      seen = Map.put(seen, name, true)
      collect_children_names(get_sub_agents(agent), seen)
    end
  end

  defp collect_children_names([], seen), do: {:ok, seen}

  defp collect_children_names([child | rest], seen) do
    case collect_names(child, seen) do
      {:ok, updated} -> collect_children_names(rest, updated)
      {:error, _} = err -> err
    end
  end

  defp agent_name(agent) do
    agent.__struct__.name(agent)
  end

  defp get_sub_agents(agent) do
    if function_exported?(agent.__struct__, :sub_agents, 1) do
      agent.__struct__.sub_agents(agent)
    else
      []
    end
  end
end
