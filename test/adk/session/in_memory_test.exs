defmodule ADK.Session.InMemoryTest do
  use ExUnit.Case, async: true

  alias ADK.Event
  alias ADK.Event.Actions
  alias ADK.Session.InMemory
  alias ADK.Types.Content

  setup do
    name = :"test_session_#{System.unique_integer([:positive])}"
    prefix = :"test_#{System.unique_integer([:positive])}"
    {:ok, pid} = InMemory.start_link(name: name, table_prefix: prefix)
    {:ok, server: pid}
  end

  describe "create/2" do
    test "creates a session with generated id", %{server: server} do
      {:ok, session} = InMemory.create(server, app_name: "app1", user_id: "user1")

      assert session.app_name == "app1"
      assert session.user_id == "user1"
      assert is_binary(session.id)
      assert session.events == []
      assert session.state == %{}
    end

    test "creates a session with specified id", %{server: server} do
      {:ok, session} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      assert session.id == "s1"
    end

    test "rejects duplicate session ids", %{server: server} do
      {:ok, _} = InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")
      result = InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")
      assert {:error, :already_exists} = result
    end

    test "applies initial state with scoped deltas", %{server: server} do
      initial = %{
        "app:model" => "gpt-4",
        "user:theme" => "dark",
        "counter" => 0
      }

      {:ok, session} =
        InMemory.create(server,
          app_name: "app1",
          user_id: "user1",
          session_id: "s1",
          state: initial
        )

      assert session.state["app:model"] == "gpt-4"
      assert session.state["user:theme"] == "dark"
      assert session.state["counter"] == 0
    end
  end

  describe "get/2" do
    test "retrieves a session", %{server: server} do
      {:ok, created} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      {:ok, fetched} =
        InMemory.get(server, app_name: "app1", user_id: "user1", session_id: "s1")

      assert fetched.id == created.id
    end

    test "returns error for missing session", %{server: server} do
      result = InMemory.get(server, app_name: "app1", user_id: "user1", session_id: "nope")
      assert {:error, :not_found} = result
    end

    test "filters by num_recent_events", %{server: server} do
      {:ok, session} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      for i <- 1..5 do
        event = Event.new(content: Content.new_from_text("model", "msg #{i}"))
        :ok = InMemory.append_event(server, session, event)
      end

      {:ok, fetched} =
        InMemory.get(server,
          app_name: "app1",
          user_id: "user1",
          session_id: "s1",
          num_recent_events: 2
        )

      assert length(fetched.events) == 2
    end

    test "filters by after timestamp", %{server: server} do
      {:ok, session} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      early = DateTime.utc_now()
      Process.sleep(10)

      event1 =
        Event.new(content: Content.new_from_text("model", "old"), timestamp: early)

      :ok = InMemory.append_event(server, session, event1)

      Process.sleep(10)
      cutoff = DateTime.utc_now()
      Process.sleep(10)

      later = DateTime.utc_now()

      event2 =
        Event.new(content: Content.new_from_text("model", "new"), timestamp: later)

      :ok = InMemory.append_event(server, session, event2)

      {:ok, fetched} =
        InMemory.get(server,
          app_name: "app1",
          user_id: "user1",
          session_id: "s1",
          after: cutoff
        )

      assert length(fetched.events) == 1
    end
  end

  describe "list/2" do
    test "lists sessions for app/user", %{server: server} do
      {:ok, _} = InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")
      {:ok, _} = InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s2")
      {:ok, _} = InMemory.create(server, app_name: "app1", user_id: "user2", session_id: "s3")

      {:ok, sessions} = InMemory.list(server, app_name: "app1", user_id: "user1")
      assert length(sessions) == 2

      {:ok, sessions2} = InMemory.list(server, app_name: "app1", user_id: "user2")
      assert length(sessions2) == 1
    end
  end

  describe "delete/2" do
    test "deletes a session", %{server: server} do
      {:ok, _} = InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")
      :ok = InMemory.delete(server, app_name: "app1", user_id: "user1", session_id: "s1")

      result = InMemory.get(server, app_name: "app1", user_id: "user1", session_id: "s1")
      assert {:error, :not_found} = result
    end
  end

  describe "append_event/3" do
    test "appends events to a session", %{server: server} do
      {:ok, session} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      event = Event.new(content: Content.new_from_text("model", "hello"))
      :ok = InMemory.append_event(server, session, event)

      {:ok, fetched} =
        InMemory.get(server, app_name: "app1", user_id: "user1", session_id: "s1")

      assert length(fetched.events) == 1
    end

    test "skips partial events", %{server: server} do
      {:ok, session} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      event = Event.new(content: Content.new_from_text("model", "hel"), partial: true)
      :ok = InMemory.append_event(server, session, event)

      {:ok, fetched} =
        InMemory.get(server, app_name: "app1", user_id: "user1", session_id: "s1")

      assert fetched.events == []
    end

    test "updates session-local state via event delta", %{server: server} do
      {:ok, session} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      event =
        Event.new(
          content: Content.new_from_text("model", "hello"),
          actions: %Actions{state_delta: %{"counter" => 1}}
        )

      :ok = InMemory.append_event(server, session, event)

      {:ok, fetched} =
        InMemory.get(server, app_name: "app1", user_id: "user1", session_id: "s1")

      assert fetched.state["counter"] == 1
    end

    test "app-shared state visible across sessions", %{server: server} do
      {:ok, s1} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      {:ok, _s2} =
        InMemory.create(server, app_name: "app1", user_id: "user2", session_id: "s2")

      event =
        Event.new(
          content: Content.new_from_text("model", "set"),
          actions: %Actions{state_delta: %{"app:model" => "gpt-4"}}
        )

      :ok = InMemory.append_event(server, s1, event)

      # Session 2 (different user) should see the app state
      {:ok, fetched_s2} =
        InMemory.get(server, app_name: "app1", user_id: "user2", session_id: "s2")

      assert fetched_s2.state["app:model"] == "gpt-4"
    end

    test "user-specific state shared across sessions for same user", %{server: server} do
      {:ok, s1} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      {:ok, _s2} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s2")

      {:ok, _s3} =
        InMemory.create(server, app_name: "app1", user_id: "user2", session_id: "s3")

      event =
        Event.new(
          content: Content.new_from_text("model", "set"),
          actions: %Actions{state_delta: %{"user:pref" => "vi"}}
        )

      :ok = InMemory.append_event(server, s1, event)

      # Same user, different session: should see user state
      {:ok, fetched_s2} =
        InMemory.get(server, app_name: "app1", user_id: "user1", session_id: "s2")

      assert fetched_s2.state["user:pref"] == "vi"

      # Different user: should NOT see user state
      {:ok, fetched_s3} =
        InMemory.get(server, app_name: "app1", user_id: "user2", session_id: "s3")

      refute Map.has_key?(fetched_s3.state, "user:pref")
    end

    test "temp state is evicted from persisted event delta", %{server: server} do
      {:ok, session} =
        InMemory.create(server, app_name: "app1", user_id: "user1", session_id: "s1")

      event =
        Event.new(
          content: Content.new_from_text("model", "hello"),
          actions: %Actions{
            state_delta: %{"temp:scratch" => "val", "counter" => 1}
          }
        )

      :ok = InMemory.append_event(server, session, event)

      {:ok, fetched} =
        InMemory.get(server, app_name: "app1", user_id: "user1", session_id: "s1")

      # Temp key should not be in persisted event delta
      [persisted_event] = fetched.events
      refute Map.has_key?(persisted_event.actions.state_delta, "temp:scratch")
      assert persisted_event.actions.state_delta["counter"] == 1

      # Temp key should not appear in session state
      refute Map.has_key?(fetched.state, "temp:scratch")
    end
  end
end
