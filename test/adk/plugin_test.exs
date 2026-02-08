defmodule ADK.PluginTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{CallbackContext, InvocationContext, LlmAgent}
  alias ADK.Event
  alias ADK.Model.{LlmResponse, Mock}
  alias ADK.Plugin
  alias ADK.Plugin.Manager, as: PluginManager
  alias ADK.Runner
  alias ADK.Session.InMemory
  alias ADK.Tool.FunctionTool
  alias ADK.Types
  alias ADK.Types.{Content, Part}

  # -- Plugin.Manager unit tests --

  describe "Plugin.Manager.new/1" do
    test "creates manager with unique names" do
      p1 = Plugin.new(name: "p1")
      p2 = Plugin.new(name: "p2")
      assert {:ok, %PluginManager{plugins: [^p1, ^p2]}} = PluginManager.new([p1, p2])
    end

    test "rejects duplicate names" do
      p1 = Plugin.new(name: "dup")
      p2 = Plugin.new(name: "dup")
      assert {:error, "Duplicate plugin names: dup"} = PluginManager.new([p1, p2])
    end

    test "empty list succeeds" do
      assert {:ok, %PluginManager{plugins: []}} = PluginManager.new([])
    end
  end

  describe "nil plugin_manager no-op" do
    test "all run_* functions pass through with nil" do
      ctx = %InvocationContext{}
      cb_ctx = CallbackContext.new(ctx)

      content = %Content{role: "user", parts: []}

      assert {nil, ^ctx} = PluginManager.run_on_user_message(nil, ctx, content)
      assert {nil, ^ctx} = PluginManager.run_before_run(nil, ctx)
      assert :ok = PluginManager.run_after_run(nil, ctx)
      assert {nil, ^ctx} = PluginManager.run_on_event(nil, ctx, %Event{})
      assert {nil, ^cb_ctx} = PluginManager.run_before_agent(nil, cb_ctx)
      assert {nil, ^cb_ctx} = PluginManager.run_after_agent(nil, cb_ctx)
      assert {nil, ^cb_ctx} = PluginManager.run_before_model(nil, cb_ctx, %{})
      assert {nil, ^cb_ctx} = PluginManager.run_after_model(nil, cb_ctx, %LlmResponse{})
      assert {nil, ^cb_ctx} = PluginManager.run_on_model_error(nil, cb_ctx, %{}, :error)
    end
  end

  describe "plugin with nil callbacks passes through" do
    test "nil callbacks are skipped" do
      plugin = Plugin.new(name: "empty")
      {:ok, mgr} = PluginManager.new([plugin])

      ctx = %InvocationContext{}
      cb_ctx = CallbackContext.new(ctx)

      assert {nil, ^ctx} = PluginManager.run_before_run(mgr, ctx)
      assert {nil, ^cb_ctx} = PluginManager.run_before_agent(mgr, cb_ctx)
      assert {nil, ^cb_ctx} = PluginManager.run_before_model(mgr, cb_ctx, %{})
    end
  end

  describe "multiple plugins chain (first non-nil wins)" do
    test "first plugin short-circuits, second not called" do
      response = %Content{role: "model", parts: [%Part{text: "from p1"}]}

      p1 =
        Plugin.new(
          name: "p1",
          before_agent: fn cb_ctx -> {response, cb_ctx} end
        )

      p2 =
        Plugin.new(
          name: "p2",
          before_agent: fn _cb_ctx -> raise "should not be called" end
        )

      {:ok, mgr} = PluginManager.new([p1, p2])
      cb_ctx = CallbackContext.new(%InvocationContext{})

      assert {^response, _} = PluginManager.run_before_agent(mgr, cb_ctx)
    end

    test "first returns nil, second gets called" do
      response = %Content{role: "model", parts: [%Part{text: "from p2"}]}

      p1 =
        Plugin.new(
          name: "p1",
          before_agent: fn cb_ctx -> {nil, cb_ctx} end
        )

      p2 =
        Plugin.new(
          name: "p2",
          before_agent: fn cb_ctx -> {response, cb_ctx} end
        )

      {:ok, mgr} = PluginManager.new([p1, p2])
      cb_ctx = CallbackContext.new(%InvocationContext{})

      assert {^response, _} = PluginManager.run_before_agent(mgr, cb_ctx)
    end
  end

  # -- Integration tests via Runner --

  defp setup_runner(opts) do
    n = System.unique_integer([:positive])
    {:ok, svc} = InMemory.start_link(name: :"plugin_svc_#{n}", table_prefix: :"plugin_#{n}")

    model = Mock.new(responses: Keyword.get(opts, :responses, []))
    tools = Keyword.get(opts, :tools, [])
    plugins = Keyword.get(opts, :plugins, [])

    agent = %LlmAgent{
      name: "test_agent",
      model: model,
      tools: tools
    }

    {:ok, runner} =
      Runner.new(
        app_name: "test_app",
        root_agent: agent,
        session_service: svc,
        plugins: plugins
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

  describe "plugin before_agent short-circuits agent execution" do
    test "returns plugin content instead of running LLM" do
      short_circuit_content = %Content{
        role: "model",
        parts: [%Part{text: "blocked by plugin"}]
      }

      plugin =
        Plugin.new(
          name: "blocker",
          before_agent: fn cb_ctx -> {short_circuit_content, cb_ctx} end
        )

      runner = setup_runner(responses: [model_response("should not appear")], plugins: [plugin])
      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      # Should have user event committed + plugin short-circuit event
      model_events = Enum.reject(events, &(&1.author == "user"))
      assert length(model_events) == 1
      [event] = model_events
      assert event.content.parts |> hd() |> Map.get(:text) == "blocked by plugin"
    end
  end

  describe "plugin before_model short-circuits LLM call" do
    test "returns plugin response instead of calling model" do
      fake_response = model_response("cached result")

      plugin =
        Plugin.new(
          name: "cache",
          before_model: fn cb_ctx, _request -> {fake_response, cb_ctx} end
        )

      runner = setup_runner(responses: [], plugins: [plugin])
      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      model_events = Enum.reject(events, &(&1.author == "user"))
      assert model_events != []
      [event | _] = model_events
      assert event.content.parts |> hd() |> Map.get(:text) == "cached result"
    end
  end

  describe "plugin after_model replaces response" do
    test "modifies LLM response" do
      replacement = model_response("modified by plugin")

      plugin =
        Plugin.new(
          name: "modifier",
          after_model: fn cb_ctx, _response -> {replacement, cb_ctx} end
        )

      runner = setup_runner(responses: [model_response("original")], plugins: [plugin])
      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      model_events = Enum.reject(events, &(&1.author == "user"))
      [event | _] = model_events
      assert event.content.parts |> hd() |> Map.get(:text) == "modified by plugin"
    end
  end

  describe "plugin before_tool short-circuits tool execution" do
    test "returns cached tool result" do
      tool =
        FunctionTool.new(
          name: "my_tool",
          description: "A tool",
          parameters: %{},
          handler: fn _ctx, _args -> {:ok, %{"result" => "real"}} end
        )

      # Model calls the tool
      tool_call_response = %LlmResponse{
        content: %Content{
          role: "model",
          parts: [
            %Part{
              function_call: %Types.FunctionCall{name: "my_tool", id: "fc1", args: %{}}
            }
          ]
        }
      }

      # Model responds after tool
      final_response = model_response("done")

      plugin =
        Plugin.new(
          name: "tool_cache",
          before_tool: fn tool_ctx, _tool, _args ->
            {%{"result" => "cached"}, tool_ctx}
          end
        )

      runner =
        setup_runner(
          responses: [tool_call_response, final_response],
          tools: [tool],
          plugins: [plugin]
        )

      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      # Find the tool response event
      tool_events =
        Enum.filter(events, fn e ->
          e.content && e.content.role == "user" && e.author != "user"
        end)

      assert tool_events != []
      [tool_event | _] = tool_events

      fr =
        tool_event.content.parts
        |> Enum.find_value(fn p -> p.function_response end)

      assert fr.response == %{"result" => "cached"}
    end
  end

  describe "plugin after_tool replaces result" do
    test "modifies tool result" do
      tool =
        FunctionTool.new(
          name: "my_tool",
          description: "A tool",
          parameters: %{},
          handler: fn _ctx, _args -> {:ok, %{"result" => "original"}} end
        )

      tool_call_response = %LlmResponse{
        content: %Content{
          role: "model",
          parts: [
            %Part{
              function_call: %Types.FunctionCall{name: "my_tool", id: "fc1", args: %{}}
            }
          ]
        }
      }

      final_response = model_response("done")

      plugin =
        Plugin.new(
          name: "tool_modifier",
          after_tool: fn tool_ctx, _tool, _args, _result ->
            {%{"result" => "modified"}, tool_ctx}
          end
        )

      runner =
        setup_runner(
          responses: [tool_call_response, final_response],
          tools: [tool],
          plugins: [plugin]
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

      assert fr.response == %{"result" => "modified"}
    end
  end

  describe "plugin on_user_message modifies content" do
    test "transforms user message before processing" do
      modified = %Content{
        role: Types.role_user(),
        parts: [%Part{text: "transformed input"}]
      }

      plugin =
        Plugin.new(
          name: "input_transform",
          on_user_message: fn ctx, _content -> {modified, ctx} end
        )

      runner = setup_runner(responses: [model_response("ok")], plugins: [plugin])
      events = runner |> Runner.run("u1", "s1", user_msg("original")) |> Enum.to_list()

      # The events should exist — we just verify no crash
      assert events != []
    end
  end

  describe "plugin on_event modifies event" do
    test "transforms events as they are yielded" do
      plugin =
        Plugin.new(
          name: "event_tagger",
          on_event: fn ctx, event ->
            tagged = %{event | custom_metadata: %{"tagged" => true}}
            {tagged, ctx}
          end
        )

      runner = setup_runner(responses: [model_response("hi")], plugins: [plugin])
      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      model_events = Enum.reject(events, &(&1.author == "user"))
      assert Enum.all?(model_events, fn e -> e.custom_metadata == %{"tagged" => true} end)
    end
  end

  describe "plugin before_run short-circuits entire run" do
    test "returns content without running agent" do
      short_circuit = %Content{
        role: "model",
        parts: [%Part{text: "run blocked"}]
      }

      plugin =
        Plugin.new(
          name: "run_blocker",
          before_run: fn ctx -> {short_circuit, ctx} end
        )

      runner = setup_runner(responses: [model_response("should not run")], plugins: [plugin])
      events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      model_events = Enum.reject(events, &(&1.author == "user"))
      assert length(model_events) == 1
      [event] = model_events
      assert event.content.parts |> hd() |> Map.get(:text) == "run blocked"
    end
  end

  describe "plugin after_run notification" do
    test "receives notification after run completes" do
      test_pid = self()

      plugin =
        Plugin.new(
          name: "notifier",
          after_run: fn _ctx ->
            send(test_pid, :after_run_called)
            :ok
          end
        )

      runner = setup_runner(responses: [model_response("hi")], plugins: [plugin])
      _events = runner |> Runner.run("u1", "s1", user_msg("hi")) |> Enum.to_list()

      assert_received :after_run_called
    end
  end

  describe "Runner rejects duplicate plugin names" do
    test "returns error from new/1" do
      p1 = Plugin.new(name: "same")
      p2 = Plugin.new(name: "same")

      n = System.unique_integer([:positive])
      {:ok, svc} = InMemory.start_link(name: :"dup_svc_#{n}", table_prefix: :"dup_#{n}")
      model = Mock.new(responses: [])

      agent = %LlmAgent{name: "test", model: model}

      result =
        Runner.new(
          app_name: "app",
          root_agent: agent,
          session_service: svc,
          plugins: [p1, p2]
        )

      assert {:error, "Duplicate plugin names: same"} = result
    end
  end

  describe "plugin on_tool_error recovery" do
    test "recovers from tool error with plugin" do
      tool =
        FunctionTool.new(
          name: "failing_tool",
          description: "Always fails",
          parameters: %{},
          handler: fn _ctx, _args -> {:error, "boom"} end
        )

      tool_call_response = %LlmResponse{
        content: %Content{
          role: "model",
          parts: [
            %Part{
              function_call: %Types.FunctionCall{name: "failing_tool", id: "fc1", args: %{}}
            }
          ]
        }
      }

      final_response = model_response("recovered")

      plugin =
        Plugin.new(
          name: "error_handler",
          on_tool_error: fn tool_ctx, _tool, _error ->
            {%{"recovered" => true}, tool_ctx}
          end
        )

      runner =
        setup_runner(
          responses: [tool_call_response, final_response],
          tools: [tool],
          plugins: [plugin]
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

      assert fr.response == %{"recovered" => true}
    end
  end
end
