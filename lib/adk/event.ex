defmodule ADK.Event.Actions do
  @moduledoc """
  Side-effect actions produced by an event.

  Actions capture state changes, artifact updates, agent transfers,
  and other effects that should be applied when processing an event.
  """

  @type t :: %__MODULE__{
          state_delta: map(),
          artifact_delta: map(),
          transfer_to_agent: String.t() | nil,
          escalate: boolean(),
          skip_summarization: boolean(),
          requested_tool_confirmations: [map()]
        }

  defstruct state_delta: %{},
            artifact_delta: %{},
            transfer_to_agent: nil,
            escalate: false,
            skip_summarization: false,
            requested_tool_confirmations: []
end

defmodule ADK.Event do
  @moduledoc """
  Represents an interaction event in an agent session.

  Events are the core unit of communication in ADK's event-sourced architecture.
  Each event captures content, metadata, and side-effect actions produced during
  agent execution.
  """

  alias ADK.Types
  alias ADK.Types.Content

  @type t :: %__MODULE__{
          id: String.t(),
          timestamp: DateTime.t(),
          invocation_id: String.t() | nil,
          branch: String.t() | nil,
          author: String.t() | nil,
          content: Content.t() | nil,
          partial: boolean(),
          turn_complete: boolean(),
          interrupted: boolean(),
          error_code: String.t() | nil,
          error_message: String.t() | nil,
          finish_reason: String.t() | nil,
          usage_metadata: map() | nil,
          citation_metadata: map() | nil,
          grounding_metadata: map() | nil,
          custom_metadata: map() | nil,
          actions: ADK.Event.Actions.t(),
          long_running_tool_ids: [String.t()]
        }

  defstruct [
    :id,
    :timestamp,
    :invocation_id,
    :branch,
    :author,
    :content,
    :error_code,
    :error_message,
    :finish_reason,
    :usage_metadata,
    :citation_metadata,
    :grounding_metadata,
    :custom_metadata,
    partial: false,
    turn_complete: false,
    interrupted: false,
    actions: %ADK.Event.Actions{},
    long_running_tool_ids: []
  ]

  @doc """
  Creates a new event with a generated UUID and current timestamp.

  Accepts a keyword list of fields to set on the event.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    struct!(
      __MODULE__,
      Keyword.merge(
        [id: UUID.uuid4(), timestamp: DateTime.utc_now()],
        opts
      )
    )
  end

  @doc """
  Determines if this event represents a final response.

  Mirrors Go ADK's IsFinalResponse() logic:
  - Returns true if skip_summarization is set or long_running_tool_ids present
  - Returns false if content has function calls/responses or event is partial
  - Returns true otherwise (it's a final text response)
  """
  @spec final_response?(t()) :: boolean()
  def final_response?(%__MODULE__{} = event) do
    cond do
      event.actions.skip_summarization -> true
      event.long_running_tool_ids != [] -> true
      event.partial -> false
      event.content != nil and Types.has_function_calls?(event.content) -> false
      event.content != nil and Types.has_function_responses?(event.content) -> false
      true -> true
    end
  end
end
