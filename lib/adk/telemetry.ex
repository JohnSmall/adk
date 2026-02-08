defmodule ADK.Telemetry do
  @moduledoc """
  Dual telemetry instrumentation for the ADK.

  Emits both OpenTelemetry spans and Elixir `:telemetry` events
  for LLM calls, tool calls, and merged tool operations.

  ## OpenTelemetry Spans

  - `"call_llm"` — wraps model generate_content calls
  - `"execute_tool {name}"` — wraps individual tool executions
  - `"execute_tool (merged)"` — marks the combined tool results event

  ## :telemetry Events

  - `[:adk, :llm, :start | :stop | :exception]`
  - `[:adk, :tool, :start | :stop | :exception]`
  """

  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Wraps an LLM call with a "call_llm" span and :telemetry events.

  Metadata should include `:model_name`, `:invocation_id`, `:session_id`.
  """
  @spec span_llm_call(map(), (-> result)) :: result when result: var
  def span_llm_call(metadata, fun) do
    start_time = System.monotonic_time()
    system_time = System.system_time()

    :telemetry.execute([:adk, :llm, :start], %{system_time: system_time}, metadata)

    attributes = llm_attributes(metadata)

    Tracer.with_span "call_llm", %{attributes: attributes} do
      try do
        result = fun.()
        duration = System.monotonic_time() - start_time
        :telemetry.execute([:adk, :llm, :stop], %{duration: duration}, metadata)
        result
      rescue
        e ->
          duration = System.monotonic_time() - start_time
          error_meta = Map.put(metadata, :error, Exception.message(e))
          :telemetry.execute([:adk, :llm, :exception], %{duration: duration}, error_meta)

          Tracer.set_status(:error, Exception.message(e))
          reraise e, __STACKTRACE__
      end
    end
  end

  @doc """
  Wraps a tool call with an "execute_tool {name}" span and :telemetry events.

  Metadata should include `:tool_name`, `:function_call_id`.
  """
  @spec span_tool_call(map(), (-> result)) :: result when result: var
  def span_tool_call(metadata, fun) do
    start_time = System.monotonic_time()
    system_time = System.system_time()
    tool_name = Map.get(metadata, :tool_name, "unknown")

    :telemetry.execute([:adk, :tool, :start], %{system_time: system_time}, metadata)

    attributes = tool_attributes(metadata)

    Tracer.with_span "execute_tool #{tool_name}", %{attributes: attributes} do
      try do
        result = fun.()
        duration = System.monotonic_time() - start_time
        :telemetry.execute([:adk, :tool, :stop], %{duration: duration}, metadata)
        result
      rescue
        e ->
          duration = System.monotonic_time() - start_time
          error_meta = Map.put(metadata, :error, Exception.message(e))
          :telemetry.execute([:adk, :tool, :exception], %{duration: duration}, error_meta)

          Tracer.set_status(:error, Exception.message(e))
          reraise e, __STACKTRACE__
      end
    end
  end

  @doc """
  Emits a span for merged tool results.

  Metadata should include `:event_id`.
  """
  @spec span_merged_tools(map()) :: :ok
  def span_merged_tools(metadata) do
    attributes = %{"gen_ai.operation.name" => "execute_tool"}

    Tracer.with_span "execute_tool (merged)", %{attributes: attributes} do
      Tracer.set_attribute("event.id", Map.get(metadata, :event_id, ""))
    end

    :ok
  end

  # -- Private --

  defp llm_attributes(metadata) do
    %{
      "gen_ai.system" => "elixir_adk",
      "gen_ai.request.model" => Map.get(metadata, :model_name, ""),
      "gen_ai.operation.name" => "call_llm",
      "gcp.vertex.agent.invocation_id" => Map.get(metadata, :invocation_id, ""),
      "gcp.vertex.agent.session_id" => Map.get(metadata, :session_id, "")
    }
  end

  defp tool_attributes(metadata) do
    %{
      "gen_ai.operation.name" => "execute_tool",
      "gen_ai.tool.name" => Map.get(metadata, :tool_name, ""),
      "gen_ai.tool.call.id" => Map.get(metadata, :function_call_id, "")
    }
  end
end
