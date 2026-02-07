defmodule ADK.Session.State do
  @moduledoc """
  Utilities for working with prefixed session state keys.

  State keys use prefixes to control their scope:
  - `app:` — shared across all users and sessions for an app
  - `user:` — shared across all sessions for a specific user
  - `temp:` — temporary, discarded after each invocation
  - (no prefix) — session-local state
  """

  @app_prefix "app:"
  @user_prefix "user:"
  @temp_prefix "temp:"

  def app_prefix, do: @app_prefix
  def user_prefix, do: @user_prefix
  def temp_prefix, do: @temp_prefix

  @doc """
  Returns the scope of a state key.

  ## Examples

      iex> ADK.Session.State.scope("app:model")
      :app
      iex> ADK.Session.State.scope("user:pref")
      :user
      iex> ADK.Session.State.scope("temp:scratch")
      :temp
      iex> ADK.Session.State.scope("counter")
      :session
  """
  @spec scope(String.t()) :: :app | :user | :temp | :session
  def scope(@app_prefix <> _), do: :app
  def scope(@user_prefix <> _), do: :user
  def scope(@temp_prefix <> _), do: :temp
  def scope(_), do: :session

  @doc """
  Splits a state delta map into `{app_delta, user_delta, session_delta}`.

  Strips prefixes from app/user keys. Discards temp keys entirely.
  Session-local keys (no prefix) are kept as-is.
  """
  @spec extract_deltas(map()) :: {map(), map(), map()}
  def extract_deltas(delta) when is_map(delta) do
    Enum.reduce(delta, {%{}, %{}, %{}}, fn {key, value}, {app, user, session} ->
      case scope(key) do
        :app ->
          {Map.put(app, strip_prefix(key, @app_prefix), value), user, session}

        :user ->
          {app, Map.put(user, strip_prefix(key, @user_prefix), value), session}

        :temp ->
          {app, user, session}

        :session ->
          {app, user, Map.put(session, key, value)}
      end
    end)
  end

  @doc """
  Merges app, user, and session state maps back into a single map with prefixes.
  """
  @spec merge_states(map(), map(), map()) :: map()
  def merge_states(app_state, user_state, session_state) do
    merged = %{}

    merged =
      Enum.reduce(app_state, merged, fn {k, v}, acc ->
        Map.put(acc, @app_prefix <> k, v)
      end)

    merged =
      Enum.reduce(user_state, merged, fn {k, v}, acc ->
        Map.put(acc, @user_prefix <> k, v)
      end)

    Enum.reduce(session_state, merged, fn {k, v}, acc ->
      Map.put(acc, k, v)
    end)
  end

  @doc "Removes all keys with the temp prefix from a map."
  @spec strip_temp(map()) :: map()
  def strip_temp(state) do
    Map.reject(state, fn {key, _} -> scope(key) == :temp end)
  end

  @doc "Removes all temp-prefixed keys from a delta map."
  @spec trim_temp_delta(map()) :: map()
  def trim_temp_delta(delta) do
    Map.reject(delta, fn {key, _} -> scope(key) == :temp end)
  end

  @doc "Gets a value from state by key."
  @spec get(map(), String.t()) :: any()
  def get(state, key), do: Map.get(state, key)

  @doc "Sets a value in state by key."
  @spec put(map(), String.t(), any()) :: map()
  def put(state, key, value), do: Map.put(state, key, value)

  defp strip_prefix(key, prefix) do
    String.replace_prefix(key, prefix, "")
  end
end
