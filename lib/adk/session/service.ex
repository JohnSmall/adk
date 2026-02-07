defmodule ADK.Session.Service do
  @moduledoc """
  Behaviour for session storage backends.

  Implementations manage session lifecycle (create, get, list, delete)
  and event persistence (append_event). The InMemorySessionService
  provides the default implementation.
  """

  @type opts :: keyword()

  @doc "Creates a new session."
  @callback create(server :: GenServer.server(), opts()) ::
              {:ok, ADK.Session.t()} | {:error, term()}

  @doc "Retrieves a session by identity."
  @callback get(server :: GenServer.server(), opts()) ::
              {:ok, ADK.Session.t()} | {:error, term()}

  @doc "Lists sessions matching criteria."
  @callback list(server :: GenServer.server(), opts()) ::
              {:ok, [ADK.Session.t()]} | {:error, term()}

  @doc "Deletes a session."
  @callback delete(server :: GenServer.server(), opts()) ::
              :ok | {:error, term()}

  @doc "Appends an event to a session."
  @callback append_event(server :: GenServer.server(), ADK.Session.t(), ADK.Event.t()) ::
              :ok | {:error, term()}
end
