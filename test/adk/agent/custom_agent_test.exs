defmodule ADK.Agent.CustomAgentTest do
  use ExUnit.Case, async: true

  alias ADK.Agent.{CallbackContext, Config, CustomAgent, InvocationContext}
  alias ADK.Event
  alias ADK.Types.Content

  defp make_ctx do
    %InvocationContext{invocation_id: "inv-1", branch: "main"}
  end

  describe "basic agent" do
    test "name and description from config" do
      agent =
        CustomAgent.new(%Config{
          name: "test_agent",
          description: "A test agent"
        })

      assert CustomAgent.name(agent) == "test_agent"
      assert CustomAgent.description(agent) == "A test agent"
    end

    test "run with no run function yields no events" do
      agent = CustomAgent.new(%Config{name: "empty"})
      events = Enum.to_list(CustomAgent.run(agent, make_ctx()))
      assert events == []
    end

    test "run yields events from run function" do
      agent =
        CustomAgent.new(%Config{
          name: "greeter",
          run: fn _ctx ->
            [Event.new(content: Content.new_from_text("model", "hello"))]
          end
        })

      events = Enum.to_list(CustomAgent.run(agent, make_ctx()))
      assert length(events) == 1
      assert hd(events).content.parts |> hd() |> Map.get(:text) == "hello"
    end

    test "sets author on events without one" do
      agent =
        CustomAgent.new(%Config{
          name: "auto_author",
          run: fn _ctx ->
            [Event.new(content: Content.new_from_text("model", "hello"))]
          end
        })

      [event] = Enum.to_list(CustomAgent.run(agent, make_ctx()))
      assert event.author == "auto_author"
    end

    test "preserves existing author on events" do
      agent =
        CustomAgent.new(%Config{
          name: "auto_author",
          run: fn _ctx ->
            [Event.new(content: Content.new_from_text("model", "hello"), author: "original")]
          end
        })

      [event] = Enum.to_list(CustomAgent.run(agent, make_ctx()))
      assert event.author == "original"
    end
  end

  describe "before_agent_callbacks" do
    test "nil content continues to run function" do
      agent =
        CustomAgent.new(%Config{
          name: "agent",
          before_agent_callbacks: [
            fn cb_ctx -> {nil, cb_ctx} end
          ],
          run: fn _ctx ->
            [Event.new(content: Content.new_from_text("model", "from run"))]
          end
        })

      events = Enum.to_list(CustomAgent.run(agent, make_ctx()))
      assert length(events) == 1
      assert hd(events).content.parts |> hd() |> Map.get(:text) == "from run"
    end

    test "non-nil content short-circuits run function" do
      agent =
        CustomAgent.new(%Config{
          name: "agent",
          before_agent_callbacks: [
            fn cb_ctx ->
              {Content.new_from_text("model", "intercepted"), cb_ctx}
            end
          ],
          run: fn _ctx ->
            [Event.new(content: Content.new_from_text("model", "should not reach"))]
          end
        })

      events = Enum.to_list(CustomAgent.run(agent, make_ctx()))
      assert length(events) == 1
      assert hd(events).content.parts |> hd() |> Map.get(:text) == "intercepted"
    end

    test "state changes from callback appear in event actions" do
      agent =
        CustomAgent.new(%Config{
          name: "agent",
          before_agent_callbacks: [
            fn cb_ctx ->
              cb_ctx = CallbackContext.set_state(cb_ctx, "key", "value")
              {Content.new_from_text("model", "done"), cb_ctx}
            end
          ]
        })

      [event] = Enum.to_list(CustomAgent.run(agent, make_ctx()))
      assert event.actions.state_delta["key"] == "value"
    end
  end

  describe "after_agent_callbacks" do
    test "runs after the main run function" do
      agent =
        CustomAgent.new(%Config{
          name: "agent",
          run: fn _ctx ->
            [Event.new(content: Content.new_from_text("model", "from run"))]
          end,
          after_agent_callbacks: [
            fn cb_ctx -> {nil, cb_ctx} end
          ]
        })

      events = Enum.to_list(CustomAgent.run(agent, make_ctx()))
      assert length(events) == 1
    end

    test "non-nil content produces an additional event" do
      agent =
        CustomAgent.new(%Config{
          name: "agent",
          run: fn _ctx ->
            [Event.new(content: Content.new_from_text("model", "from run"))]
          end,
          after_agent_callbacks: [
            fn cb_ctx ->
              {Content.new_from_text("model", "after"), cb_ctx}
            end
          ]
        })

      events = Enum.to_list(CustomAgent.run(agent, make_ctx()))
      assert length(events) == 2

      texts =
        Enum.map(events, fn e -> hd(e.content.parts).text end)

      assert texts == ["from run", "after"]
    end
  end

  describe "sub_agents" do
    test "returns sub_agents from config" do
      child = CustomAgent.new(%Config{name: "child"})

      parent =
        CustomAgent.new(%Config{
          name: "parent",
          sub_agents: [child]
        })

      assert CustomAgent.sub_agents(parent) == [child]
    end
  end
end
