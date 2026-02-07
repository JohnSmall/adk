defmodule ADK.EventTest do
  use ExUnit.Case, async: true

  alias ADK.Event
  alias ADK.Event.Actions
  alias ADK.Types.{Content, FunctionCall, FunctionResponse, Part}

  describe "new/1" do
    test "generates UUID and timestamp" do
      event = Event.new()
      assert is_binary(event.id)
      assert String.length(event.id) == 36
      assert %DateTime{} = event.timestamp
    end

    test "accepts keyword options" do
      event = Event.new(author: "test_agent", branch: "main")
      assert event.author == "test_agent"
      assert event.branch == "main"
    end

    test "defaults partial to false" do
      event = Event.new()
      assert event.partial == false
    end

    test "defaults actions to empty Actions struct" do
      event = Event.new()
      assert %Actions{state_delta: %{}} = event.actions
    end
  end

  describe "final_response?/1" do
    test "returns true for simple text event" do
      event = Event.new(content: Content.new_from_text("model", "hello"))
      assert Event.final_response?(event)
    end

    test "returns true when skip_summarization is set" do
      event =
        Event.new(
          content: Content.new_from_text("model", "hello"),
          actions: %Actions{skip_summarization: true}
        )

      assert Event.final_response?(event)
    end

    test "returns true when long_running_tool_ids present" do
      event = Event.new(long_running_tool_ids: ["tool_1"])
      assert Event.final_response?(event)
    end

    test "returns false for partial events" do
      event = Event.new(content: Content.new_from_text("model", "hel"), partial: true)
      refute Event.final_response?(event)
    end

    test "returns false when content has function calls" do
      content = %Content{
        role: "model",
        parts: [Part.new_function_call(%FunctionCall{name: "get_weather"})]
      }

      event = Event.new(content: content)
      refute Event.final_response?(event)
    end

    test "returns false when content has function responses" do
      content = %Content{
        role: "user",
        parts: [Part.new_function_response(%FunctionResponse{name: "get_weather"})]
      }

      event = Event.new(content: content)
      refute Event.final_response?(event)
    end

    test "returns true for event with nil content" do
      event = Event.new(content: nil)
      assert Event.final_response?(event)
    end

    test "skip_summarization overrides function calls" do
      content = %Content{
        role: "model",
        parts: [Part.new_function_call(%FunctionCall{name: "f"})]
      }

      event = Event.new(content: content, actions: %Actions{skip_summarization: true})
      assert Event.final_response?(event)
    end

    test "long_running_tool_ids overrides partial" do
      event = Event.new(partial: true, long_running_tool_ids: ["t1"])
      assert Event.final_response?(event)
    end
  end
end
