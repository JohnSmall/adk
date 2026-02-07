defmodule ADK.Agent.TreeTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{Config, CustomAgent, Tree}

  defp make_agent(name, children \\ []) do
    CustomAgent.new(%Config{name: name, sub_agents: children})
  end

  describe "find_agent/2" do
    test "finds root agent by name" do
      root = make_agent("root")
      assert {:ok, ^root} = Tree.find_agent(root, "root")
    end

    test "finds nested agent by name" do
      grandchild = make_agent("gc")
      child = make_agent("child", [grandchild])
      root = make_agent("root", [child])

      assert {:ok, ^grandchild} = Tree.find_agent(root, "gc")
      assert {:ok, ^child} = Tree.find_agent(root, "child")
    end

    test "returns error for missing agent" do
      root = make_agent("root")
      assert :error = Tree.find_agent(root, "nonexistent")
    end
  end

  describe "build_parent_map/1" do
    test "maps child names to parent agents" do
      child1 = make_agent("c1")
      child2 = make_agent("c2")
      root = make_agent("root", [child1, child2])

      parent_map = Tree.build_parent_map(root)

      assert parent_map["c1"] == root
      assert parent_map["c2"] == root
      refute Map.has_key?(parent_map, "root")
    end

    test "handles nested hierarchy" do
      gc = make_agent("gc")
      child = make_agent("child", [gc])
      root = make_agent("root", [child])

      parent_map = Tree.build_parent_map(root)

      assert parent_map["child"] == root
      assert parent_map["gc"] == child
    end
  end

  describe "validate_unique_names/1" do
    test "returns ok for unique names" do
      c1 = make_agent("c1")
      c2 = make_agent("c2")
      root = make_agent("root", [c1, c2])

      assert {:ok, names} = Tree.validate_unique_names(root)
      assert MapSet.member?(names, "root")
      assert MapSet.member?(names, "c1")
      assert MapSet.member?(names, "c2")
    end

    test "returns error for duplicate names" do
      c1 = make_agent("dup")
      c2 = make_agent("dup")
      root = make_agent("root", [c1, c2])

      assert {:error, "duplicate agent name: dup"} = Tree.validate_unique_names(root)
    end

    test "detects duplicates in nested hierarchy" do
      gc = make_agent("root")
      child = make_agent("child", [gc])
      root = make_agent("root", [child])

      assert {:error, "duplicate agent name: root"} = Tree.validate_unique_names(root)
    end
  end
end
