defmodule ADK.Memory.InMemoryTest do
  use ExUnit.Case, async: true

  alias ADK.Event
  alias ADK.Memory.InMemory
  alias ADK.Session
  alias ADK.Types.Content
  alias ADK.Types.Part

  setup do
    name = :"test_memory_#{System.unique_integer([:positive])}"
    prefix = :"test_mem_#{System.unique_integer([:positive])}"
    {:ok, pid} = InMemory.start_link(name: name, table_prefix: prefix)
    {:ok, server: pid}
  end

  defp make_session(app_name, user_id, session_id, events) do
    %Session{
      id: session_id,
      app_name: app_name,
      user_id: user_id,
      events: events
    }
  end

  defp text_event(text, author \\ "model") do
    Event.new(
      author: author,
      content: Content.new_from_text("model", text)
    )
  end

  describe "add_session/2" do
    test "stores content from session events", %{server: server} do
      session = make_session("app1", "user1", "s1", [text_event("hello world")])
      assert :ok = InMemory.add_session(server, session)

      {:ok, results} = InMemory.search(server, query: "hello", app_name: "app1", user_id: "user1")
      assert length(results) == 1
      assert hd(results).author == "model"
    end

    test "re-adding session replaces entries", %{server: server} do
      session1 = make_session("app1", "user1", "s1", [text_event("alpha beta")])
      :ok = InMemory.add_session(server, session1)

      session2 = make_session("app1", "user1", "s1", [text_event("gamma delta")])
      :ok = InMemory.add_session(server, session2)

      {:ok, results} = InMemory.search(server, query: "alpha", app_name: "app1", user_id: "user1")
      assert results == []

      {:ok, results} = InMemory.search(server, query: "gamma", app_name: "app1", user_id: "user1")
      assert length(results) == 1
    end

    test "ignores events without text content", %{server: server} do
      blob_event =
        Event.new(
          author: "model",
          content: %Content{role: "model", parts: [Part.new_inline_data("binary", "image/png")]}
        )

      session = make_session("app1", "user1", "s1", [blob_event])
      :ok = InMemory.add_session(server, session)

      {:ok, results} = InMemory.search(server, query: "binary", app_name: "app1", user_id: "user1")
      assert results == []
    end

    test "ignores events with nil content", %{server: server} do
      nil_event = Event.new(author: "system", content: nil)
      session = make_session("app1", "user1", "s1", [nil_event])
      :ok = InMemory.add_session(server, session)

      {:ok, results} = InMemory.search(server, query: "system", app_name: "app1", user_id: "user1")
      assert results == []
    end
  end

  describe "search/2" do
    test "finds matching entries by word", %{server: server} do
      session =
        make_session("app1", "user1", "s1", [
          text_event("The quick brown fox"),
          text_event("jumped over the lazy dog")
        ])

      :ok = InMemory.add_session(server, session)

      {:ok, results} = InMemory.search(server, query: "fox", app_name: "app1", user_id: "user1")
      assert length(results) == 1

      {:ok, results} = InMemory.search(server, query: "lazy", app_name: "app1", user_id: "user1")
      assert length(results) == 1
    end

    test "returns empty list for no matches", %{server: server} do
      session = make_session("app1", "user1", "s1", [text_event("hello world")])
      :ok = InMemory.add_session(server, session)

      {:ok, results} =
        InMemory.search(server, query: "nonexistent", app_name: "app1", user_id: "user1")

      assert results == []
    end

    test "returns empty list for empty query", %{server: server} do
      session = make_session("app1", "user1", "s1", [text_event("hello world")])
      :ok = InMemory.add_session(server, session)

      {:ok, results} = InMemory.search(server, query: "", app_name: "app1", user_id: "user1")
      assert results == []
    end

    test "scopes by app_name and user_id", %{server: server} do
      session1 = make_session("app1", "user1", "s1", [text_event("secret data")])
      session2 = make_session("app2", "user2", "s2", [text_event("other data")])

      :ok = InMemory.add_session(server, session1)
      :ok = InMemory.add_session(server, session2)

      {:ok, results} = InMemory.search(server, query: "secret", app_name: "app1", user_id: "user1")
      assert length(results) == 1

      {:ok, results} = InMemory.search(server, query: "secret", app_name: "app2", user_id: "user2")
      assert results == []
    end

    test "search is case-insensitive", %{server: server} do
      session = make_session("app1", "user1", "s1", [text_event("Hello WORLD")])
      :ok = InMemory.add_session(server, session)

      {:ok, results} = InMemory.search(server, query: "hello", app_name: "app1", user_id: "user1")
      assert length(results) == 1

      {:ok, results} = InMemory.search(server, query: "WORLD", app_name: "app1", user_id: "user1")
      assert length(results) == 1
    end

    test "searches across multiple sessions for same user", %{server: server} do
      session1 = make_session("app1", "user1", "s1", [text_event("alpha content")])
      session2 = make_session("app1", "user1", "s2", [text_event("beta content")])

      :ok = InMemory.add_session(server, session1)
      :ok = InMemory.add_session(server, session2)

      {:ok, results} =
        InMemory.search(server, query: "content", app_name: "app1", user_id: "user1")

      assert length(results) == 2
    end
  end
end
