defmodule ADK.Memory.Service do
  @moduledoc """
  Behaviour for memory storage backends.

  Memory services store cross-session knowledge extracted from session events
  and provide search capabilities for retrieving relevant memories.
  """

  @type opts :: keyword()

  @doc """
  Adds a session's events to memory storage.

  Extracts text content from session events, indexes it for search,
  and stores it keyed by the session's app_name and user_id.
  """
  @callback add_session(server :: GenServer.server(), session :: ADK.Session.t()) ::
              :ok | {:error, term()}

  @doc """
  Searches memory for entries matching the given criteria.

  Options:
  - `:query` — search text (words are matched against stored entries)
  - `:app_name` — scope to a specific application
  - `:user_id` — scope to a specific user
  """
  @callback search(server :: GenServer.server(), opts()) ::
              {:ok, [ADK.Memory.Entry.t()]} | {:error, term()}
end
