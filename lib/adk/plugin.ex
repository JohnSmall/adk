defmodule ADK.Plugin do
  @moduledoc """
  Plugin struct for hooking into the agent lifecycle.

  Plugins provide callbacks at Runner, Agent, Model, and Tool levels.
  Callbacks follow the standard `{value | nil, updated_context}` pattern:
  non-nil values short-circuit, nil continues to the next plugin/callback.

  ## Example

      plugin = ADK.Plugin.new(
        name: "logging",
        before_model: fn cb_ctx, _request ->
          IO.puts("Model called for \#{ADK.Agent.CallbackContext.agent_name(cb_ctx)}")
          {nil, cb_ctx}
        end
      )
  """

  alias ADK.Agent.{CallbackContext, InvocationContext}
  alias ADK.Event
  alias ADK.Model.LlmResponse
  alias ADK.Tool.Context, as: ToolContext
  alias ADK.Types.Content

  @type on_user_message_callback ::
          (InvocationContext.t(), Content.t() -> {Content.t() | nil, InvocationContext.t()})

  @type before_run_callback ::
          (InvocationContext.t() -> {Content.t() | nil, InvocationContext.t()})

  @type after_run_callback :: (InvocationContext.t() -> :ok)

  @type on_event_callback ::
          (InvocationContext.t(), Event.t() -> {Event.t() | nil, InvocationContext.t()})

  @type before_agent_callback ::
          (CallbackContext.t() -> {Content.t() | nil, CallbackContext.t()})

  @type after_agent_callback ::
          (CallbackContext.t() -> {Content.t() | nil, CallbackContext.t()})

  @type before_model_callback ::
          (CallbackContext.t(), ADK.Model.LlmRequest.t() ->
             {LlmResponse.t() | nil, CallbackContext.t()})

  @type after_model_callback ::
          (CallbackContext.t(), LlmResponse.t() -> {LlmResponse.t() | nil, CallbackContext.t()})

  @type on_model_error_callback ::
          (CallbackContext.t(), ADK.Model.LlmRequest.t(), term() ->
             {LlmResponse.t() | nil, CallbackContext.t()})

  @type before_tool_callback ::
          (ToolContext.t(), struct(), map() -> {map() | nil, ToolContext.t()})

  @type after_tool_callback ::
          (ToolContext.t(), struct(), map(), map() -> {map() | nil, ToolContext.t()})

  @type on_tool_error_callback ::
          (ToolContext.t(), struct(), map() -> {map() | nil, ToolContext.t()})

  @type t :: %__MODULE__{
          name: String.t(),
          on_user_message: on_user_message_callback() | nil,
          on_event: on_event_callback() | nil,
          before_run: before_run_callback() | nil,
          after_run: after_run_callback() | nil,
          before_agent: before_agent_callback() | nil,
          after_agent: after_agent_callback() | nil,
          before_model: before_model_callback() | nil,
          after_model: after_model_callback() | nil,
          on_model_error: on_model_error_callback() | nil,
          before_tool: before_tool_callback() | nil,
          after_tool: after_tool_callback() | nil,
          on_tool_error: on_tool_error_callback() | nil
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    :on_user_message,
    :on_event,
    :before_run,
    :after_run,
    :before_agent,
    :after_agent,
    :before_model,
    :after_model,
    :on_model_error,
    :before_tool,
    :after_tool,
    :on_tool_error
  ]

  @doc """
  Creates a new plugin from keyword options.

  Requires `:name`. All callback fields are optional (default nil).
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    struct!(__MODULE__, opts)
  end
end
