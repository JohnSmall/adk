defmodule ADK.Tool.ToolsetTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.LlmAgent
  alias ADK.Model.{LlmResponse, Mock}
  alias ADK.Runner
  alias ADK.Session.InMemory
  alias ADK.Tool.FunctionTool
  alias ADK.Types
  alias ADK.Types.{Content, Part}

  # -- Test toolset implementations --

  defmodule StaticToolset do
    @behaviour ADK.Tool.Toolset

    defstruct tools: []

    @impl true
    def name(_ts), do: "static_toolset"

    @impl true
    def tools(%__MODULE__{tools: tools}, _ctx), do: {:ok, tools}
  end

  defmodule EmptyToolset do
    @behaviour ADK.Tool.Toolset

    defstruct []

    @impl true
    def name(_ts), do: "empty_toolset"

    @impl true
    def tools(_ts, _ctx), do: {:ok, []}
  end

  defmodule ErrorToolset do
    @behaviour ADK.Tool.Toolset

    defstruct []

    @impl true
    def name(_ts), do: "error_toolset"

    @impl true
    def tools(_ts, _ctx), do: {:error, "connection failed"}
  end

  defmodule ContextAwareToolset do
    @behaviour ADK.Tool.Toolset

    defstruct []

    @impl true
    def name(_ts), do: "context_aware"

    @impl true
    def tools(_ts, ctx) do
      tool =
        FunctionTool.new(
          name: "ctx_tool_#{ctx.invocation_id |> String.slice(0..7)}",
          description: "Context-derived tool",
          handler: fn _ctx, _args -> {:ok, %{"from_context" => true}} end
        )

      {:ok, [tool]}
    end
  end

  defmodule SpyToolset do
    @behaviour ADK.Tool.Toolset

    defstruct [:pid]

    @impl true
    def name(_ts), do: "spy_toolset"

    @impl true
    def tools(%__MODULE__{pid: pid}, ctx) do
      send(pid, {:toolset_ctx, ctx.invocation_id})
      {:ok, []}
    end
  end

  defp setup_runner(opts) do
    n = System.unique_integer([:positive])
    {:ok, svc} = InMemory.start_link(name: :"ts_svc_#{n}", table_prefix: :"ts_#{n}")

    model = Mock.new(responses: Keyword.fetch!(opts, :responses))
    tools = Keyword.get(opts, :tools, [])
    toolsets = Keyword.get(opts, :toolsets, [])

    agent = %LlmAgent{
      name: "test_agent",
      model: model,
      tools: tools,
      toolsets: toolsets
    }

    {:ok, runner} =
      Runner.new(
        app_name: "test_app",
        root_agent: agent,
        session_service: svc
      )

    runner
  end

  defp user_msg(text) do
    %Content{role: Types.role_user(), parts: [%Part{text: text}]}
  end

  defp model_response(text) do
    %LlmResponse{
      content: %Content{role: "model", parts: [%Part{text: text}]},
      turn_complete: true
    }
  end

  describe "toolset provides tools at runtime" do
    test "toolset tools are callable by LLM via Flow" do
      dynamic_tool =
        FunctionTool.new(
          name: "dynamic_tool",
          description: "A dynamically provided tool",
          handler: fn _ctx, _args -> {:ok, %{"dynamic" => true}} end
        )

      toolset = %StaticToolset{tools: [dynamic_tool]}

      tool_call_response = %LlmResponse{
        content: %Content{
          role: "model",
          parts: [
            %Part{
              function_call: %Types.FunctionCall{name: "dynamic_tool", id: "fc1", args: %{}}
            }
          ]
        }
      }

      final_response = model_response("done")

      runner = setup_runner(responses: [tool_call_response, final_response], toolsets: [toolset])
      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      tool_events =
        Enum.filter(events, fn e ->
          e.content && e.content.role == "user" && e.author != "user"
        end)

      assert tool_events != []
      [tool_event | _] = tool_events

      fr =
        tool_event.content.parts
        |> Enum.find_value(fn p -> p.function_response end)

      assert fr.response == %{"dynamic" => true}
    end
  end

  describe "multiple toolsets merged with static tools" do
    test "static and toolset tools coexist" do
      static_tool =
        FunctionTool.new(
          name: "static_tool",
          description: "A static tool",
          handler: fn _ctx, _args -> {:ok, %{"static" => true}} end
        )

      dynamic_tool =
        FunctionTool.new(
          name: "dynamic_tool",
          description: "A dynamic tool",
          handler: fn _ctx, _args -> {:ok, %{"dynamic" => true}} end
        )

      toolset = %StaticToolset{tools: [dynamic_tool]}

      # Call static tool
      tool_call_response = %LlmResponse{
        content: %Content{
          role: "model",
          parts: [
            %Part{
              function_call: %Types.FunctionCall{name: "static_tool", id: "fc1", args: %{}}
            }
          ]
        }
      }

      final_response = model_response("done")

      runner =
        setup_runner(
          responses: [tool_call_response, final_response],
          tools: [static_tool],
          toolsets: [toolset]
        )

      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      tool_events =
        Enum.filter(events, fn e ->
          e.content && e.content.role == "user" && e.author != "user"
        end)

      [tool_event | _] = tool_events

      fr =
        tool_event.content.parts
        |> Enum.find_value(fn p -> p.function_response end)

      assert fr.response == %{"static" => true}
    end
  end

  describe "toolset returning empty list" do
    test "empty toolset works fine" do
      runner =
        setup_runner(
          responses: [model_response("hi")],
          toolsets: [%EmptyToolset{}]
        )

      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()
      assert events != []
    end
  end

  describe "toolset error returns empty (does not crash)" do
    test "error toolset gracefully degrades" do
      runner =
        setup_runner(
          responses: [model_response("hi")],
          toolsets: [%ErrorToolset{}]
        )

      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()
      assert events != []
    end
  end

  describe "InvocationContext passed to tools/2" do
    test "toolset receives context with invocation_id" do
      test_pid = self()

      n = System.unique_integer([:positive])
      {:ok, svc} = InMemory.start_link(name: :"spy_svc_#{n}", table_prefix: :"spy_#{n}")
      model = Mock.new(responses: [model_response("hi")])

      agent = %LlmAgent{
        name: "test_agent",
        model: model,
        toolsets: [%SpyToolset{pid: test_pid}]
      }

      {:ok, runner} =
        Runner.new(
          app_name: "test_app",
          root_agent: agent,
          session_service: svc
        )

      _events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      assert_received {:toolset_ctx, invocation_id}
      assert is_binary(invocation_id)
    end
  end
end
