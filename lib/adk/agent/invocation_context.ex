defmodule ADK.Agent.InvocationContext do
  @moduledoc """
  Immutable context threaded through agent invocations.

  Carries the current agent, session, services, and execution metadata.
  Callers create updated copies via the `with_*` helpers.
  """

  @type t :: %__MODULE__{
          agent: struct() | nil,
          session: ADK.Session.t() | nil,
          invocation_id: String.t() | nil,
          branch: String.t() | nil,
          user_content: ADK.Types.Content.t() | nil,
          run_config: ADK.RunConfig.t(),
          ended: boolean(),
          session_service: GenServer.server() | nil,
          artifact_service: term(),
          memory_service: term()
        }

  defstruct [
    :agent,
    :session,
    :invocation_id,
    :branch,
    :user_content,
    :session_service,
    :artifact_service,
    :memory_service,
    run_config: %ADK.RunConfig{},
    ended: false
  ]

  @doc "Marks the invocation as ended."
  @spec end_invocation(t()) :: t()
  def end_invocation(%__MODULE__{} = ctx), do: %{ctx | ended: true}

  @doc "Returns whether the invocation has ended."
  @spec ended?(t()) :: boolean()
  def ended?(%__MODULE__{ended: ended}), do: ended

  @doc "Returns a new context with a different agent."
  @spec with_agent(t(), struct()) :: t()
  def with_agent(%__MODULE__{} = ctx, agent), do: %{ctx | agent: agent}

  @doc "Returns a new context with a different branch."
  @spec with_branch(t(), String.t()) :: t()
  def with_branch(%__MODULE__{} = ctx, branch), do: %{ctx | branch: branch}
end
