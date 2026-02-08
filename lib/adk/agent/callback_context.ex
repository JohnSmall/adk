defmodule ADK.Agent.CallbackContext do
  @moduledoc """
  Context available to before/after agent callbacks.

  Wraps an `InvocationContext` and provides an `actions` field
  for callbacks to record side effects (state changes, transfers, etc.).
  """

  alias ADK.Agent.InvocationContext
  alias ADK.Event.Actions
  alias ADK.Memory.InMemory, as: MemoryService

  @type t :: %__MODULE__{
          invocation_context: InvocationContext.t(),
          actions: Actions.t()
        }

  defstruct invocation_context: %InvocationContext{},
            actions: %Actions{}

  @doc "Creates a new callback context from an invocation context."
  @spec new(InvocationContext.t()) :: t()
  def new(%InvocationContext{} = ctx) do
    %__MODULE__{invocation_context: ctx, actions: %Actions{}}
  end

  @doc "Returns the agent name from the underlying invocation context."
  @spec agent_name(t()) :: String.t() | nil
  def agent_name(%__MODULE__{invocation_context: ctx}) do
    if ctx.agent, do: ctx.agent.__struct__.name(ctx.agent), else: nil
  end

  @doc "Returns the invocation ID."
  @spec invocation_id(t()) :: String.t() | nil
  def invocation_id(%__MODULE__{invocation_context: ctx}), do: ctx.invocation_id

  @doc "Returns the session ID."
  @spec session_id(t()) :: String.t() | nil
  def session_id(%__MODULE__{invocation_context: ctx}) do
    if ctx.session, do: ctx.session.id, else: nil
  end

  @doc "Returns the app name."
  @spec app_name(t()) :: String.t() | nil
  def app_name(%__MODULE__{invocation_context: ctx}) do
    if ctx.session, do: ctx.session.app_name, else: nil
  end

  @doc "Returns the user ID."
  @spec user_id(t()) :: String.t() | nil
  def user_id(%__MODULE__{invocation_context: ctx}) do
    if ctx.session, do: ctx.session.user_id, else: nil
  end

  @doc "Gets a value from session state, checking the actions state_delta first."
  @spec get_state(t(), String.t()) :: any()
  def get_state(%__MODULE__{actions: actions, invocation_context: ctx}, key) do
    case Map.fetch(actions.state_delta, key) do
      {:ok, value} -> value
      :error -> if ctx.session, do: Map.get(ctx.session.state, key), else: nil
    end
  end

  @doc "Sets a value in the actions state_delta."
  @spec set_state(t(), String.t(), any()) :: t()
  def set_state(%__MODULE__{actions: actions} = cb_ctx, key, value) do
    new_delta = Map.put(actions.state_delta, key, value)
    %{cb_ctx | actions: %{actions | state_delta: new_delta}}
  end

  @doc """
  Searches memory for entries matching the query.

  Returns `{:ok, [Entry.t()]}` or `{:ok, []}` if no memory service is configured.
  """
  @spec search_memory(t(), String.t()) :: {:ok, [ADK.Memory.Entry.t()]}
  def search_memory(%__MODULE__{invocation_context: ctx}, query) do
    if ctx.memory_service do
      MemoryService.search(ctx.memory_service,
        query: query,
        app_name: ctx.session.app_name,
        user_id: ctx.session.user_id
      )
    else
      {:ok, []}
    end
  end
end
