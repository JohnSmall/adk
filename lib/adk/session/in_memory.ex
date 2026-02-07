defmodule ADK.Session.InMemory do
  @moduledoc """
  In-memory session service backed by ETS tables.

  Uses a GenServer to own three ETS tables:
  - `sessions` — stores session data keyed by `{app_name, user_id, session_id}`
  - `app_state` — app-level state keyed by `app_name`
  - `user_state` — user-level state keyed by `{app_name, user_id}`

  Reads go directly to ETS (with `read_concurrency: true`).
  Writes are serialized through GenServer calls.
  """

  use GenServer

  @behaviour ADK.Session.Service

  alias ADK.Event
  alias ADK.Session
  alias ADK.Session.State, as: StateUtil

  # -- Client API --

  @doc "Starts the InMemorySessionService."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl ADK.Session.Service
  def create(server, opts) do
    GenServer.call(server, {:create, opts})
  end

  @impl ADK.Session.Service
  def get(server, opts) do
    GenServer.call(server, {:get, opts})
  end

  @impl ADK.Session.Service
  def list(server, opts) do
    GenServer.call(server, {:list, opts})
  end

  @impl ADK.Session.Service
  def delete(server, opts) do
    GenServer.call(server, {:delete, opts})
  end

  @impl ADK.Session.Service
  def append_event(server, %Session{} = session, %Event{} = event) do
    GenServer.call(server, {:append_event, session, event})
  end

  # -- GenServer Callbacks --

  @impl GenServer
  def init(opts) do
    table_prefix = Keyword.get(opts, :table_prefix, :adk_session)

    sessions_table =
      :ets.new(:"#{table_prefix}_sessions", [
        :set,
        :protected,
        read_concurrency: true
      ])

    app_state_table =
      :ets.new(:"#{table_prefix}_app_state", [
        :set,
        :protected,
        read_concurrency: true
      ])

    user_state_table =
      :ets.new(:"#{table_prefix}_user_state", [
        :set,
        :protected,
        read_concurrency: true
      ])

    state = %{
      sessions: sessions_table,
      app_state: app_state_table,
      user_state: user_state_table
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:create, opts}, _from, state) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.get(opts, :session_id) || UUID.uuid4()
    initial_state = Keyword.get(opts, :state, %{})

    key = {app_name, user_id, session_id}

    case :ets.lookup(state.sessions, key) do
      [{^key, _}] ->
        {:reply, {:error, :already_exists}, state}

      [] ->
        # Extract and apply initial state deltas
        {app_delta, user_delta, session_delta} = StateUtil.extract_deltas(initial_state)

        apply_app_delta(state.app_state, app_name, app_delta)
        apply_user_delta(state.user_state, app_name, user_id, user_delta)

        now = DateTime.utc_now()

        session_record = %{
          state: session_delta,
          events: [],
          last_update_time: now
        }

        :ets.insert(state.sessions, {key, session_record})

        # Build merged state for the response
        merged = build_merged_state(state, app_name, user_id, session_delta)

        session = %Session{
          id: session_id,
          app_name: app_name,
          user_id: user_id,
          state: merged,
          events: [],
          last_update_time: now
        }

        {:reply, {:ok, session}, state}
    end
  end

  @impl GenServer
  def handle_call({:get, opts}, _from, state) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.fetch!(opts, :session_id)
    num_recent = Keyword.get(opts, :num_recent_events)
    after_time = Keyword.get(opts, :after)

    key = {app_name, user_id, session_id}

    case :ets.lookup(state.sessions, key) do
      [] ->
        {:reply, {:error, :not_found}, state}

      [{^key, record}] ->
        events = filter_events(record.events, num_recent, after_time)
        merged = build_merged_state(state, app_name, user_id, record.state)

        session = %Session{
          id: session_id,
          app_name: app_name,
          user_id: user_id,
          state: merged,
          events: events,
          last_update_time: record.last_update_time
        }

        {:reply, {:ok, session}, state}
    end
  end

  @impl GenServer
  def handle_call({:list, opts}, _from, state) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)

    sessions =
      :ets.tab2list(state.sessions)
      |> Enum.filter(fn {{an, uid, _sid}, _record} ->
        an == app_name and uid == user_id
      end)
      |> Enum.map(fn {{_an, _uid, sid}, record} ->
        merged = build_merged_state(state, app_name, user_id, record.state)

        %Session{
          id: sid,
          app_name: app_name,
          user_id: user_id,
          state: merged,
          events: record.events,
          last_update_time: record.last_update_time
        }
      end)

    {:reply, {:ok, sessions}, state}
  end

  @impl GenServer
  def handle_call({:delete, opts}, _from, state) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.fetch!(opts, :session_id)

    key = {app_name, user_id, session_id}
    :ets.delete(state.sessions, key)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:append_event, session, event}, _from, state) do
    # Skip partial events
    if event.partial do
      {:reply, :ok, state}
    else
      key = {session.app_name, session.user_id, session.id}

      case :ets.lookup(state.sessions, key) do
        [] ->
          {:reply, {:error, :not_found}, state}

        [{^key, record}] ->
          delta = event.actions.state_delta

          # Extract scoped deltas
          {app_delta, user_delta, session_delta} = StateUtil.extract_deltas(delta)

          # Apply to scoped tables
          apply_app_delta(state.app_state, session.app_name, app_delta)
          apply_user_delta(state.user_state, session.app_name, session.user_id, user_delta)

          # Update session state (merge session_delta)
          new_session_state = Map.merge(record.state, session_delta)

          # Trim temp from the persisted event's delta
          trimmed_delta = StateUtil.trim_temp_delta(delta)
          trimmed_event = put_in(event.actions.state_delta, trimmed_delta)

          now = DateTime.utc_now()

          updated_record = %{
            record
            | events: record.events ++ [trimmed_event],
              state: new_session_state,
              last_update_time: now
          }

          :ets.insert(state.sessions, {key, updated_record})
          {:reply, :ok, state}
      end
    end
  end

  # -- Private Helpers --

  defp build_merged_state(tables, app_name, user_id, session_state) do
    app_st = get_app_state(tables.app_state, app_name)
    user_st = get_user_state(tables.user_state, app_name, user_id)
    StateUtil.merge_states(app_st, user_st, session_state)
  end

  defp get_app_state(table, app_name) do
    case :ets.lookup(table, app_name) do
      [{^app_name, st}] -> st
      [] -> %{}
    end
  end

  defp get_user_state(table, app_name, user_id) do
    key = {app_name, user_id}

    case :ets.lookup(table, key) do
      [{^key, st}] -> st
      [] -> %{}
    end
  end

  defp apply_app_delta(_table, _app_name, delta) when map_size(delta) == 0, do: :ok

  defp apply_app_delta(table, app_name, delta) do
    current = get_app_state(table, app_name)
    :ets.insert(table, {app_name, Map.merge(current, delta)})
  end

  defp apply_user_delta(_table, _app_name, _user_id, delta) when map_size(delta) == 0, do: :ok

  defp apply_user_delta(table, app_name, user_id, delta) do
    key = {app_name, user_id}
    current = get_user_state(table, app_name, user_id)
    :ets.insert(table, {key, Map.merge(current, delta)})
  end

  defp filter_events(events, nil, nil), do: events

  defp filter_events(events, num_recent, nil) when is_integer(num_recent) do
    Enum.take(events, -num_recent)
  end

  defp filter_events(events, nil, %DateTime{} = after_time) do
    Enum.filter(events, fn e ->
      e.timestamp != nil and DateTime.compare(e.timestamp, after_time) == :gt
    end)
  end

  defp filter_events(events, num_recent, %DateTime{} = after_time) do
    events
    |> filter_events(nil, after_time)
    |> filter_events(num_recent, nil)
  end
end
