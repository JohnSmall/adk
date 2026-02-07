defmodule ADK.Session.StateTest do
  use ExUnit.Case, async: true

  alias ADK.Session.State

  describe "scope/1" do
    test "identifies app-scoped keys" do
      assert State.scope("app:model_name") == :app
    end

    test "identifies user-scoped keys" do
      assert State.scope("user:preference") == :user
    end

    test "identifies temp-scoped keys" do
      assert State.scope("temp:scratch") == :temp
    end

    test "identifies session-scoped keys (no prefix)" do
      assert State.scope("counter") == :session
      assert State.scope("result") == :session
    end
  end

  describe "extract_deltas/1" do
    test "splits delta into app, user, and session maps" do
      delta = %{
        "app:model" => "gpt-4",
        "user:theme" => "dark",
        "temp:scratch" => "ignored",
        "counter" => 42
      }

      {app, user, session} = State.extract_deltas(delta)

      assert app == %{"model" => "gpt-4"}
      assert user == %{"theme" => "dark"}
      assert session == %{"counter" => 42}
    end

    test "discards temp keys" do
      delta = %{"temp:a" => 1, "temp:b" => 2}
      {app, user, session} = State.extract_deltas(delta)

      assert app == %{}
      assert user == %{}
      assert session == %{}
    end

    test "handles empty delta" do
      assert {%{}, %{}, %{}} = State.extract_deltas(%{})
    end
  end

  describe "merge_states/3" do
    test "merges with prefixes" do
      merged = State.merge_states(%{"model" => "gpt-4"}, %{"theme" => "dark"}, %{"counter" => 1})

      assert merged == %{
               "app:model" => "gpt-4",
               "user:theme" => "dark",
               "counter" => 1
             }
    end

    test "handles empty maps" do
      assert State.merge_states(%{}, %{}, %{}) == %{}
    end
  end

  describe "strip_temp/1" do
    test "removes temp-prefixed keys" do
      state = %{"temp:x" => 1, "app:y" => 2, "counter" => 3}
      result = State.strip_temp(state)

      assert result == %{"app:y" => 2, "counter" => 3}
    end
  end

  describe "trim_temp_delta/1" do
    test "removes temp keys from delta" do
      delta = %{"temp:scratch" => "val", "counter" => 5}
      assert State.trim_temp_delta(delta) == %{"counter" => 5}
    end
  end

  describe "get/2 and put/3" do
    test "get retrieves value by key" do
      state = %{"foo" => "bar"}
      assert State.get(state, "foo") == "bar"
      assert State.get(state, "missing") == nil
    end

    test "put sets value by key" do
      state = State.put(%{}, "foo", "bar")
      assert state == %{"foo" => "bar"}
    end
  end

  describe "prefix constants" do
    test "returns correct prefixes" do
      assert State.app_prefix() == "app:"
      assert State.user_prefix() == "user:"
      assert State.temp_prefix() == "temp:"
    end
  end
end
