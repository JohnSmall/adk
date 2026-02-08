defmodule ADK.Artifact.InMemory do
  @moduledoc """
  In-memory artifact service backed by an ETS table.

  Keys are `{app_name, user_id, session_id, filename, version}`,
  values are `Part.t()`. Filenames prefixed with `"user:"` are stored
  with `session_id = "user"` so they are shared across sessions.
  """

  use GenServer

  @behaviour ADK.Artifact.Service

  @user_scope_prefix "user:"
  @user_session_id "user"

  # -- Client API --

  @doc "Starts the InMemory artifact service."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl ADK.Artifact.Service
  def save(server, opts), do: GenServer.call(server, {:save, opts})

  @impl ADK.Artifact.Service
  def load(server, opts), do: GenServer.call(server, {:load, opts})

  @impl ADK.Artifact.Service
  def delete(server, opts), do: GenServer.call(server, {:delete, opts})

  @impl ADK.Artifact.Service
  def list(server, opts), do: GenServer.call(server, {:list, opts})

  @impl ADK.Artifact.Service
  def versions(server, opts), do: GenServer.call(server, {:versions, opts})

  # -- GenServer Callbacks --

  @impl GenServer
  def init(opts) do
    table_prefix = Keyword.get(opts, :table_prefix, :adk_artifact)

    table =
      :ets.new(:"#{table_prefix}_artifacts", [
        :set,
        :protected,
        read_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call({:save, opts}, _from, state) do
    filename = Keyword.fetch!(opts, :filename)

    case validate_filename(filename) do
      :ok ->
        do_save(state, opts)

      {:error, _} = err ->
        {:reply, err, state}
    end
  end

  @impl GenServer
  def handle_call({:load, opts}, _from, state) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.fetch!(opts, :session_id)
    filename = Keyword.fetch!(opts, :filename)
    version = Keyword.get(opts, :version, 0)

    sid = resolve_session_id(filename, session_id)
    result = do_load(state.table, app_name, user_id, sid, filename, version)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:delete, opts}, _from, state) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.fetch!(opts, :session_id)
    filename = Keyword.fetch!(opts, :filename)
    version = Keyword.get(opts, :version, 0)

    sid = resolve_session_id(filename, session_id)
    do_delete(state.table, app_name, user_id, sid, filename, version)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:list, opts}, _from, state) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.fetch!(opts, :session_id)

    filenames = do_list(state.table, app_name, user_id, session_id)
    {:reply, {:ok, filenames}, state}
  end

  @impl GenServer
  def handle_call({:versions, opts}, _from, state) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.fetch!(opts, :session_id)
    filename = Keyword.fetch!(opts, :filename)

    sid = resolve_session_id(filename, session_id)
    vers = do_versions(state.table, app_name, user_id, sid, filename)
    {:reply, {:ok, vers}, state}
  end

  # -- Private Helpers --

  defp validate_filename(filename) do
    if String.contains?(filename, "/") or String.contains?(filename, "\\") do
      {:error, :invalid_filename}
    else
      :ok
    end
  end

  defp resolve_session_id(filename, session_id) do
    if String.starts_with?(filename, @user_scope_prefix) do
      @user_session_id
    else
      session_id
    end
  end

  defp do_save(state, opts) do
    app_name = Keyword.fetch!(opts, :app_name)
    user_id = Keyword.fetch!(opts, :user_id)
    session_id = Keyword.fetch!(opts, :session_id)
    filename = Keyword.fetch!(opts, :filename)
    part = Keyword.fetch!(opts, :part)
    explicit_version = Keyword.get(opts, :version)

    sid = resolve_session_id(filename, session_id)

    version =
      if explicit_version && explicit_version > 0 do
        explicit_version
      else
        max_ver = find_max_version(state.table, app_name, user_id, sid, filename)
        max_ver + 1
      end

    key = {app_name, user_id, sid, filename, version}
    :ets.insert(state.table, {key, part})
    {:reply, {:ok, version}, state}
  end

  defp find_max_version(table, app_name, user_id, session_id, filename) do
    pattern = {{app_name, user_id, session_id, filename, :_}, :_}

    table
    |> :ets.match_object(pattern)
    |> Enum.reduce(0, fn {{_, _, _, _, v}, _}, max_v -> max(v, max_v) end)
  end

  defp do_load(table, app_name, user_id, session_id, filename, version)
       when version == 0 or is_nil(version) do
    pattern = {{app_name, user_id, session_id, filename, :_}, :_}

    case :ets.match_object(table, pattern) do
      [] ->
        {:error, :not_found}

      entries ->
        {_key, part} = Enum.max_by(entries, fn {{_, _, _, _, v}, _} -> v end)
        {:ok, part}
    end
  end

  defp do_load(table, app_name, user_id, session_id, filename, version) do
    key = {app_name, user_id, session_id, filename, version}

    case :ets.lookup(table, key) do
      [{^key, part}] -> {:ok, part}
      [] -> {:error, :not_found}
    end
  end

  defp do_delete(table, app_name, user_id, session_id, filename, version)
       when version == 0 or is_nil(version) do
    pattern = {{app_name, user_id, session_id, filename, :_}, :_}

    table
    |> :ets.match_object(pattern)
    |> Enum.each(fn {key, _} -> :ets.delete(table, key) end)
  end

  defp do_delete(table, app_name, user_id, session_id, filename, version) do
    key = {app_name, user_id, session_id, filename, version}
    :ets.delete(table, key)
  end

  defp do_list(table, app_name, user_id, session_id) do
    session_pattern = {{app_name, user_id, session_id, :_, :_}, :_}
    user_pattern = {{app_name, user_id, @user_session_id, :_, :_}, :_}

    session_entries = :ets.match_object(table, session_pattern)
    user_entries = :ets.match_object(table, user_pattern)

    (session_entries ++ user_entries)
    |> Enum.map(fn {{_, _, _, filename, _}, _} -> filename end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp do_versions(table, app_name, user_id, session_id, filename) do
    pattern = {{app_name, user_id, session_id, filename, :_}, :_}

    table
    |> :ets.match_object(pattern)
    |> Enum.map(fn {{_, _, _, _, v}, _} -> v end)
    |> Enum.sort(:desc)
  end
end
