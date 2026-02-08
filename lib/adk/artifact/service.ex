defmodule ADK.Artifact.Service do
  @moduledoc """
  Behaviour for artifact storage backends.

  Artifacts are versioned binary/text files associated with a session.
  Filenames starting with `"user:"` are user-scoped (shared across sessions).
  """

  @type opts :: keyword()

  @doc """
  Saves a part as an artifact. Returns `{:ok, version}` on success.

  Options: `:app_name`, `:user_id`, `:session_id`, `:filename`, `:part`.
  Optionally `:version` to overwrite a specific version.
  """
  @callback save(server :: GenServer.server(), opts()) ::
              {:ok, non_neg_integer()} | {:error, term()}

  @doc """
  Loads an artifact part. Version 0 or nil loads the latest.

  Options: `:app_name`, `:user_id`, `:session_id`, `:filename`, `:version`.
  """
  @callback load(server :: GenServer.server(), opts()) ::
              {:ok, ADK.Types.Part.t()} | {:error, term()}

  @doc """
  Deletes an artifact. Version 0 or nil deletes all versions.

  Options: `:app_name`, `:user_id`, `:session_id`, `:filename`, `:version`.
  """
  @callback delete(server :: GenServer.server(), opts()) ::
              :ok | {:error, term()}

  @doc """
  Lists artifact filenames for a session (includes user-scoped artifacts).

  Options: `:app_name`, `:user_id`, `:session_id`.
  """
  @callback list(server :: GenServer.server(), opts()) ::
              {:ok, [String.t()]} | {:error, term()}

  @doc """
  Returns version numbers for a specific artifact, descending.

  Options: `:app_name`, `:user_id`, `:session_id`, `:filename`.
  """
  @callback versions(server :: GenServer.server(), opts()) ::
              {:ok, [non_neg_integer()]} | {:error, term()}
end
