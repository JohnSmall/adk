defmodule ADK.Agent.CustomAgent do
  @moduledoc """
  A custom agent built from an `ADK.Agent.Config`.

  Wraps a user-provided run function with before/after callback hooks.
  If a before callback returns non-nil Content, the run function is skipped
  and an event with that content is emitted instead.
  """

  @behaviour ADK.Agent

  alias ADK.Agent.{CallbackContext, Config, InvocationContext}
  alias ADK.Event
  alias ADK.Types.Content

  @type t :: %__MODULE__{config: Config.t()}

  defstruct [:config]

  @doc "Creates a new custom agent from a Config."
  @spec new(Config.t()) :: t()
  def new(%Config{} = config), do: %__MODULE__{config: config}

  @impl ADK.Agent
  def name(%__MODULE__{config: config}), do: config.name

  @impl ADK.Agent
  def description(%__MODULE__{config: config}), do: config.description

  @impl ADK.Agent
  def sub_agents(%__MODULE__{config: config}), do: config.sub_agents

  @impl ADK.Agent
  def run(%__MODULE__{config: config} = _agent, %InvocationContext{} = ctx) do
    Stream.resource(
      fn -> {:before, ctx, config} end,
      &next/1,
      fn _ -> :ok end
    )
  end

  defp next({:before, ctx, config}) do
    cb_ctx = CallbackContext.new(ctx)

    case run_before_callbacks(config.before_agent_callbacks, cb_ctx) do
      {:short_circuit, content, cb_ctx} ->
        event = make_callback_event(ctx, content, cb_ctx)
        {[event], :done}

      {:continue, _cb_ctx} ->
        if config.run do
          inner_stream = config.run.(ctx)
          {[], {:stream, Enum.to_list(inner_stream), ctx, config}}
        else
          {[], {:after, ctx, config}}
        end
    end
  end

  defp next({:stream, [], ctx, config}) do
    {[], {:after, ctx, config}}
  end

  defp next({:stream, [event | rest], ctx, config}) do
    event = maybe_set_author(event, config.name)
    {[event], {:stream, rest, ctx, config}}
  end

  defp next({:after, ctx, config}) do
    cb_ctx = CallbackContext.new(ctx)

    case run_after_callbacks(config.after_agent_callbacks, cb_ctx) do
      {:short_circuit, content, cb_ctx} ->
        event = make_callback_event(ctx, content, cb_ctx)
        {[event], :done}

      {:continue, _cb_ctx} ->
        {[], :done}
    end
  end

  defp next(:done) do
    {:halt, :done}
  end

  defp run_before_callbacks([], cb_ctx), do: {:continue, cb_ctx}

  defp run_before_callbacks([callback | rest], cb_ctx) do
    case callback.(cb_ctx) do
      {%Content{} = content, updated_ctx} -> {:short_circuit, content, updated_ctx}
      {nil, updated_ctx} -> run_before_callbacks(rest, updated_ctx)
    end
  end

  defp run_after_callbacks([], cb_ctx), do: {:continue, cb_ctx}

  defp run_after_callbacks([callback | rest], cb_ctx) do
    case callback.(cb_ctx) do
      {%Content{} = content, updated_ctx} -> {:short_circuit, content, updated_ctx}
      {nil, updated_ctx} -> run_after_callbacks(rest, updated_ctx)
    end
  end

  defp make_callback_event(ctx, content, cb_ctx) do
    Event.new(
      invocation_id: ctx.invocation_id,
      branch: ctx.branch,
      author: if(ctx.agent, do: name(ctx.agent), else: nil),
      content: content,
      actions: cb_ctx.actions
    )
  end

  defp maybe_set_author(%Event{author: nil} = event, name), do: %{event | author: name}
  defp maybe_set_author(event, _name), do: event
end
