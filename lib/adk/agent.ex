defmodule ADK.Agent do
  @moduledoc """
  Behaviour for ADK agents.

  All agent types (LLM, Sequential, Parallel, Loop, Custom) implement
  this behaviour. The `run/2` callback returns a stream (Enumerable) of
  `ADK.Event` structs.
  """

  @doc "Returns the agent's unique name within the agent tree."
  @callback name(agent :: struct()) :: String.t()

  @doc "Returns the agent's description (used by LLMs for delegation decisions)."
  @callback description(agent :: struct()) :: String.t()

  @doc """
  Runs the agent and returns a stream of events.

  The returned value must be an Enumerable that yields `ADK.Event.t()` structs.
  """
  @callback run(agent :: struct(), ctx :: ADK.Agent.InvocationContext.t()) :: Enumerable.t()

  @doc "Returns the agent's sub-agents (empty list if none)."
  @callback sub_agents(agent :: struct()) :: [struct()]

  @optional_callbacks sub_agents: 1
end
