defmodule ADK.TypesTest do
  use ExUnit.Case, async: true

  alias ADK.Types
  alias ADK.Types.{Blob, Content, FunctionCall, FunctionResponse, Part}

  describe "Part" do
    test "new_text creates a text part" do
      part = Part.new_text("hello")
      assert part.text == "hello"
      assert part.function_call == nil
      assert part.thought == false
    end

    test "new_function_call creates a function call part" do
      fc = %FunctionCall{name: "get_weather", args: %{"city" => "NYC"}}
      part = Part.new_function_call(fc)
      assert part.function_call == fc
      assert part.text == nil
    end

    test "new_function_response creates a function response part" do
      fr = %FunctionResponse{name: "get_weather", response: %{"temp" => 72}}
      part = Part.new_function_response(fr)
      assert part.function_response == fr
    end

    test "new_inline_data creates a blob part" do
      part = Part.new_inline_data("binary_data", "image/png")
      assert %Blob{data: "binary_data", mime_type: "image/png"} = part.inline_data
    end

    test "function_call? returns true for function call parts" do
      fc = %FunctionCall{name: "test"}
      assert Part.function_call?(Part.new_function_call(fc))
      refute Part.function_call?(Part.new_text("hello"))
    end

    test "function_response? returns true for function response parts" do
      fr = %FunctionResponse{name: "test"}
      assert Part.function_response?(Part.new_function_response(fr))
      refute Part.function_response?(Part.new_text("hello"))
    end
  end

  describe "Content" do
    test "new_from_text creates content with a text part" do
      content = Content.new_from_text("user", "hello")
      assert content.role == "user"
      assert [%Part{text: "hello"}] = content.parts
    end

    test "new_from_bytes creates content with inline data" do
      content = Content.new_from_bytes("user", "data", "image/png")
      assert content.role == "user"
      assert [%Part{inline_data: %Blob{}}] = content.parts
    end
  end

  describe "Types helpers" do
    test "function_calls extracts all function calls from content" do
      fc1 = %FunctionCall{name: "a"}
      fc2 = %FunctionCall{name: "b"}

      content = %Content{
        role: "model",
        parts: [
          Part.new_function_call(fc1),
          Part.new_text("thinking"),
          Part.new_function_call(fc2)
        ]
      }

      assert [^fc1, ^fc2] = Types.function_calls(content)
    end

    test "function_responses extracts all function responses from content" do
      fr = %FunctionResponse{name: "test", response: %{"result" => "ok"}}

      content = %Content{
        role: "user",
        parts: [Part.new_function_response(fr), Part.new_text("done")]
      }

      assert [^fr] = Types.function_responses(content)
    end

    test "has_function_calls? returns true when present" do
      content_with = %Content{
        role: "model",
        parts: [Part.new_function_call(%FunctionCall{name: "f"})]
      }

      content_without = Content.new_from_text("model", "hello")

      assert Types.has_function_calls?(content_with)
      refute Types.has_function_calls?(content_without)
    end

    test "has_function_responses? returns true when present" do
      content_with = %Content{
        role: "user",
        parts: [Part.new_function_response(%FunctionResponse{name: "f"})]
      }

      content_without = Content.new_from_text("user", "hello")

      assert Types.has_function_responses?(content_with)
      refute Types.has_function_responses?(content_without)
    end

    test "role constants" do
      assert Types.role_user() == "user"
      assert Types.role_model() == "model"
    end
  end
end
