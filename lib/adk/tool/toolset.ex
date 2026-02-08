defmodule ADK.Tool.Toolset do
  @moduledoc """
  Behaviour for dynamic tool providers.

  Toolsets resolve tools at runtime based on the current invocation context.
  This enables lazy-loaded tools (e.g., from MCP servers) and context-dependent
  tool filtering.

  ## Example

      defmodule MyToolset do
        @behaviour ADK.Tool.Toolset

        defstruct [:api_key]

        @impl true
        def name(_toolset), do: "my_toolset"

        @impl true
        def tools(_toolset, _ctx) do
          {:ok, [MyTool.new()]}
        end
      end
  """

  @doc "Returns the toolset's unique name."
  @callback name(toolset :: struct()) :: String.t()

  @doc """
  Resolves tools for the current invocation context.

  Returns `{:ok, tools}` on success or `{:error, reason}` on failure.
  Errors are logged but do not crash the flow — the toolset returns
  an empty list in that case.
  """
  @callback tools(toolset :: struct(), ctx :: ADK.Agent.InvocationContext.t()) ::
              {:ok, [struct()]} | {:error, term()}
end
