defmodule ADK.Tool.Context do
  @moduledoc """
  Context passed to tool execution.

  Wraps a `CallbackContext` and adds `function_call_id` and its own
  `Actions`. Each tool call gets its own `ToolContext` with independent
  actions that are merged after all tool calls complete.
  """

  alias ADK.Agent.CallbackContext
  alias ADK.Artifact.InMemory, as: ArtifactService
  alias ADK.Event.Actions

  @type t :: %__MODULE__{
          callback_context: CallbackContext.t(),
          function_call_id: String.t() | nil,
          actions: Actions.t()
        }

  defstruct [
    :callback_context,
    :function_call_id,
    actions: %Actions{}
  ]

  @doc "Creates a new tool context from a callback context and function call ID."
  @spec new(CallbackContext.t(), String.t() | nil) :: t()
  def new(%CallbackContext{} = cb_ctx, function_call_id \\ nil) do
    %__MODULE__{
      callback_context: cb_ctx,
      function_call_id: function_call_id,
      actions: %Actions{}
    }
  end

  @doc "Gets a value from session state, checking tool actions then callback actions then session."
  @spec get_state(t(), String.t()) :: any()
  def get_state(%__MODULE__{actions: actions, callback_context: cb_ctx}, key) do
    case Map.fetch(actions.state_delta, key) do
      {:ok, value} -> value
      :error -> CallbackContext.get_state(cb_ctx, key)
    end
  end

  @doc "Sets a value in the tool actions state_delta."
  @spec set_state(t(), String.t(), any()) :: t()
  def set_state(%__MODULE__{actions: actions} = ctx, key, value) do
    new_delta = Map.put(actions.state_delta, key, value)
    %{ctx | actions: %{actions | state_delta: new_delta}}
  end

  @doc "Returns the agent name from the underlying callback context."
  @spec agent_name(t()) :: String.t() | nil
  def agent_name(%__MODULE__{callback_context: cb_ctx}) do
    CallbackContext.agent_name(cb_ctx)
  end

  @doc "Searches memory for entries matching the query."
  @spec search_memory(t(), String.t()) :: {:ok, [ADK.Memory.Entry.t()]}
  def search_memory(%__MODULE__{callback_context: cb_ctx}, query) do
    CallbackContext.search_memory(cb_ctx, query)
  end

  @doc """
  Saves an artifact and tracks it in the tool's artifact_delta.

  Returns `{:ok, version, updated_context}` or `{:error, reason}`.
  """
  @spec save_artifact(t(), String.t(), ADK.Types.Part.t()) ::
          {:ok, non_neg_integer(), t()} | {:error, term()}
  def save_artifact(%__MODULE__{} = ctx, filename, part) do
    inv_ctx = ctx.callback_context.invocation_context

    if inv_ctx.artifact_service do
      save_opts = [
        app_name: inv_ctx.session.app_name,
        user_id: inv_ctx.session.user_id,
        session_id: inv_ctx.session.id,
        filename: filename,
        part: part
      ]

      case ArtifactService.save(inv_ctx.artifact_service, save_opts) do
        {:ok, version} ->
          updated_delta = Map.put(ctx.actions.artifact_delta, filename, version)
          updated_ctx = %{ctx | actions: %{ctx.actions | artifact_delta: updated_delta}}
          {:ok, version, updated_ctx}

        {:error, _} = err ->
          err
      end
    else
      {:error, :no_artifact_service}
    end
  end

  @doc "Loads an artifact by filename. Version 0 (default) loads the latest."
  @spec load_artifact(t(), String.t(), non_neg_integer()) ::
          {:ok, ADK.Types.Part.t()} | {:error, term()}
  def load_artifact(%__MODULE__{} = ctx, filename, version \\ 0) do
    inv_ctx = ctx.callback_context.invocation_context

    if inv_ctx.artifact_service do
      ArtifactService.load(inv_ctx.artifact_service,
        app_name: inv_ctx.session.app_name,
        user_id: inv_ctx.session.user_id,
        session_id: inv_ctx.session.id,
        filename: filename,
        version: version
      )
    else
      {:error, :no_artifact_service}
    end
  end

  @doc "Lists artifact filenames for the current session."
  @spec list_artifacts(t()) :: {:ok, [String.t()]} | {:error, term()}
  def list_artifacts(%__MODULE__{} = ctx) do
    inv_ctx = ctx.callback_context.invocation_context

    if inv_ctx.artifact_service do
      ArtifactService.list(inv_ctx.artifact_service,
        app_name: inv_ctx.session.app_name,
        user_id: inv_ctx.session.user_id,
        session_id: inv_ctx.session.id
      )
    else
      {:error, :no_artifact_service}
    end
  end
end
