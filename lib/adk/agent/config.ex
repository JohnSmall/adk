defmodule ADK.Agent.Config do
  @moduledoc """
  Configuration struct for creating a custom agent via `ADK.Agent.CustomAgent`.
  """

  @type before_callback :: (ADK.Agent.CallbackContext.t() ->
                              {ADK.Types.Content.t() | nil, ADK.Agent.CallbackContext.t()})
  @type after_callback :: (ADK.Agent.CallbackContext.t() ->
                             {ADK.Types.Content.t() | nil, ADK.Agent.CallbackContext.t()})
  @type run_fn :: (ADK.Agent.InvocationContext.t() -> Enumerable.t())

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          sub_agents: [struct()],
          before_agent_callbacks: [before_callback()],
          run: run_fn() | nil,
          after_agent_callbacks: [after_callback()]
        }

  @enforce_keys [:name]
  defstruct [
    :name,
    :run,
    description: "",
    sub_agents: [],
    before_agent_callbacks: [],
    after_agent_callbacks: []
  ]
end
