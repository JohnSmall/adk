defmodule ADK.Tool.ContextTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{CallbackContext, InvocationContext}
  alias ADK.Session
  alias ADK.Tool.Context, as: ToolContext
  alias ADK.Types.Part

  defp make_context(state \\ %{}) do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: state}
    ctx = %InvocationContext{session: session}
    cb_ctx = CallbackContext.new(ctx)
    ToolContext.new(cb_ctx, "call_123")
  end

  defp make_context_with_services(memory_server, artifact_server) do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: %{}}

    ctx = %InvocationContext{
      session: session,
      memory_service: memory_server,
      artifact_service: artifact_server
    }

    cb_ctx = CallbackContext.new(ctx)
    ToolContext.new(cb_ctx, "call_123")
  end

  test "new creates context with function_call_id" do
    tool_ctx = make_context()
    assert tool_ctx.function_call_id == "call_123"
    assert tool_ctx.actions.state_delta == %{}
  end

  test "get_state reads from session" do
    tool_ctx = make_context(%{"city" => "London"})
    assert ToolContext.get_state(tool_ctx, "city") == "London"
  end

  test "set_state writes to actions" do
    tool_ctx = make_context()
    updated = ToolContext.set_state(tool_ctx, "result", 42)
    assert updated.actions.state_delta["result"] == 42
  end

  test "get_state prefers tool actions over session" do
    tool_ctx = make_context(%{"key" => "session_val"})
    updated = ToolContext.set_state(tool_ctx, "key", "tool_val")
    assert ToolContext.get_state(updated, "key") == "tool_val"
  end

  test "get_state falls through callback context to session" do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: %{"x" => 1}}
    ctx = %InvocationContext{session: session}
    cb_ctx = CallbackContext.set_state(CallbackContext.new(ctx), "y", 2)
    tool_ctx = ToolContext.new(cb_ctx, "call_1")

    assert ToolContext.get_state(tool_ctx, "x") == 1
    assert ToolContext.get_state(tool_ctx, "y") == 2
  end

  test "agent_name delegates to callback context" do
    # Without agent, returns nil
    tool_ctx = make_context()
    assert ToolContext.agent_name(tool_ctx) == nil
  end

  describe "search_memory/2" do
    test "returns empty list when no memory service" do
      tool_ctx = make_context()
      assert {:ok, []} = ToolContext.search_memory(tool_ctx, "hello")
    end

    test "searches memory via service" do
      mem_name = :"ctx_mem_#{System.unique_integer([:positive])}"
      mem_prefix = :"ctx_memp_#{System.unique_integer([:positive])}"
      {:ok, mem} = ADK.Memory.InMemory.start_link(name: mem_name, table_prefix: mem_prefix)

      session = %Session{
        id: "s1",
        app_name: "test",
        user_id: "u1",
        events: [
          ADK.Event.new(
            author: "model",
            content: ADK.Types.Content.new_from_text("model", "important data")
          )
        ]
      }

      :ok = ADK.Memory.InMemory.add_session(mem, session)

      tool_ctx = make_context_with_services(mem, nil)
      {:ok, results} = ToolContext.search_memory(tool_ctx, "important")
      assert length(results) == 1
    end
  end

  describe "artifact helpers" do
    setup do
      art_name = :"ctx_art_#{System.unique_integer([:positive])}"
      art_prefix = :"ctx_artp_#{System.unique_integer([:positive])}"
      {:ok, art} = ADK.Artifact.InMemory.start_link(name: art_name, table_prefix: art_prefix)
      {:ok, artifact_server: art}
    end

    test "save_artifact saves and tracks in artifact_delta", %{artifact_server: art} do
      tool_ctx = make_context_with_services(nil, art)
      part = Part.new_text("file content")

      {:ok, version, updated_ctx} = ToolContext.save_artifact(tool_ctx, "test.txt", part)
      assert version == 1
      assert updated_ctx.actions.artifact_delta == %{"test.txt" => 1}
    end

    test "load_artifact loads saved artifact", %{artifact_server: art} do
      tool_ctx = make_context_with_services(nil, art)
      part = Part.new_text("hello")

      {:ok, _version, _updated_ctx} = ToolContext.save_artifact(tool_ctx, "f.txt", part)
      {:ok, loaded} = ToolContext.load_artifact(tool_ctx, "f.txt")
      assert loaded.text == "hello"
    end

    test "list_artifacts lists saved artifacts", %{artifact_server: art} do
      tool_ctx = make_context_with_services(nil, art)

      {:ok, _, _} = ToolContext.save_artifact(tool_ctx, "b.txt", Part.new_text("b"))
      {:ok, _, _} = ToolContext.save_artifact(tool_ctx, "a.txt", Part.new_text("a"))

      {:ok, names} = ToolContext.list_artifacts(tool_ctx)
      assert names == ["a.txt", "b.txt"]
    end

    test "returns error when no artifact service" do
      tool_ctx = make_context()
      assert {:error, :no_artifact_service} = ToolContext.save_artifact(tool_ctx, "f.txt", Part.new_text("x"))
      assert {:error, :no_artifact_service} = ToolContext.load_artifact(tool_ctx, "f.txt")
      assert {:error, :no_artifact_service} = ToolContext.list_artifacts(tool_ctx)
    end
  end
end
