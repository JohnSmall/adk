defmodule ADK.Memory.InMemory do
  @moduledoc """
  In-memory memory service backed by an ETS table.

  Stores session event content indexed by `{app_name, user_id}` for
  word-based search. Each entry includes precomputed lowercase word maps
  for fast matching.
  """

  use GenServer

  @behaviour ADK.Memory.Service

  alias ADK.Memory.Entry
  alias ADK.Types.Content

  # -- Client API --

  @doc "Starts the InMemory memory service."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl ADK.Memory.Service
  def add_session(server, %ADK.Session{} = session) do
    GenServer.call(server, {:add_session, session})
  end

  @impl ADK.Memory.Service
  def search(server, opts) do
    GenServer.call(server, {:search, opts})
  end

  # -- GenServer Callbacks --

  @impl GenServer
  def init(opts) do
    table_prefix = Keyword.get(opts, :table_prefix, :adk_memory)

    table =
      :ets.new(:"#{table_prefix}_entries", [
        :set,
        :protected,
        read_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call({:add_session, session}, _from, state) do
    entries = extract_entries(session)
    key = {session.app_name, session.user_id}

    current =
      case :ets.lookup(state.table, key) do
        [{^key, sessions_map}] -> sessions_map
        [] -> %{}
      end

    updated = Map.put(current, session.id, entries)
    :ets.insert(state.table, {key, updated})
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:search, opts}, _from, state) do
    query = Keyword.get(opts, :query, "")
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)

    results = do_search(state.table, app_name, user_id, query)
    {:reply, {:ok, results}, state}
  end

  # -- Private Helpers --

  defp extract_entries(session) do
    session.events
    |> Enum.filter(&has_text_content?/1)
    |> Enum.map(fn event ->
      words = extract_words(event.content)

      %{
        content: event.content,
        author: event.author,
        timestamp: event.timestamp,
        words: words
      }
    end)
  end

  defp has_text_content?(%{content: nil}), do: false

  defp has_text_content?(%{content: %Content{parts: parts}}) do
    Enum.any?(parts, fn part -> is_binary(part.text) and part.text != "" end)
  end

  defp extract_words(%Content{parts: parts}) do
    parts
    |> Enum.flat_map(fn part ->
      if is_binary(part.text) do
        part.text
        |> String.downcase()
        |> String.split(~r/[^a-z0-9]+/, trim: true)
      else
        []
      end
    end)
    |> Map.new(fn word -> {word, true} end)
  end

  defp do_search(_table, _app_name, _user_id, ""), do: []

  defp do_search(table, app_name, user_id, query) do
    query_words =
      query
      |> String.downcase()
      |> String.split(~r/[^a-z0-9]+/, trim: true)
      |> Map.new(fn word -> {word, true} end)

    if map_size(query_words) == 0 do
      []
    else
      find_matching_entries(table, app_name, user_id, query_words)
    end
  end

  defp find_matching_entries(table, app_name, user_id, query_words) do
    key = {app_name, user_id}

    case :ets.lookup(table, key) do
      [{^key, sessions_map}] ->
        sessions_map
        |> Map.values()
        |> List.flatten()
        |> Enum.filter(fn entry -> words_intersect?(entry.words, query_words) end)
        |> Enum.map(fn entry ->
          %Entry{
            content: entry.content,
            author: entry.author,
            timestamp: entry.timestamp
          }
        end)

      [] ->
        []
    end
  end

  defp words_intersect?(entry_words, query_words) do
    Enum.any?(Map.keys(query_words), fn word ->
      Map.has_key?(entry_words, word)
    end)
  end
end
