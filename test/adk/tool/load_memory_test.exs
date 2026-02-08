defmodule ADK.Tool.LoadMemoryTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{CallbackContext, InvocationContext}
  alias ADK.Event
  alias ADK.Memory.InMemory, as: MemoryService
  alias ADK.Session
  alias ADK.Tool.Context, as: ToolContext
  alias ADK.Tool.LoadMemory
  alias ADK.Types.Content

  defp setup_memory do
    name = :"lm_mem_#{System.unique_integer([:positive])}"
    prefix = :"lm_memp_#{System.unique_integer([:positive])}"
    {:ok, pid} = MemoryService.start_link(name: name, table_prefix: prefix)
    pid
  end

  defp make_tool_ctx(memory_server) do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: %{}}

    ctx = %InvocationContext{
      session: session,
      memory_service: memory_server
    }

    cb_ctx = CallbackContext.new(ctx)
    ToolContext.new(cb_ctx, "call_1")
  end

  test "returns matching memories" do
    mem = setup_memory()

    session = %Session{
      id: "old_session",
      app_name: "test",
      user_id: "u1",
      events: [
        Event.new(author: "user", content: Content.new_from_text("user", "my favorite color is blue"))
      ]
    }

    :ok = MemoryService.add_session(mem, session)

    tool_ctx = make_tool_ctx(mem)
    tool = %LoadMemory{}

    {:ok, result} = LoadMemory.run(tool, tool_ctx, %{"query" => "favorite color"})
    assert length(result["memories"]) == 1
    assert hd(result["memories"])["text"] =~ "blue"
  end

  test "returns empty list for no matches" do
    mem = setup_memory()
    tool_ctx = make_tool_ctx(mem)
    tool = %LoadMemory{}

    {:ok, result} = LoadMemory.run(tool, tool_ctx, %{"query" => "nothing"})
    assert result["memories"] == []
  end

  test "returns empty list when no memory service" do
    session = %Session{id: "s1", app_name: "test", user_id: "u1", state: %{}}
    ctx = %InvocationContext{session: session}
    cb_ctx = CallbackContext.new(ctx)
    tool_ctx = ToolContext.new(cb_ctx, "call_1")
    tool = %LoadMemory{}

    {:ok, result} = LoadMemory.run(tool, tool_ctx, %{"query" => "hello"})
    assert result["memories"] == []
  end

  test "declaration has correct structure" do
    tool = %LoadMemory{}
    decl = LoadMemory.declaration(tool)
    assert decl["name"] == "load_memory"
    assert decl["parameters"]["properties"]["query"]["type"] == "string"
  end
end
