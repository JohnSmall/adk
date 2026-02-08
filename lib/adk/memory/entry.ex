defmodule ADK.Memory.Entry do
  @moduledoc """
  A single memory entry extracted from a session event.

  Contains the content, author, and timestamp from the original event,
  plus a precomputed word map for search matching.
  """

  @type t :: %__MODULE__{
          content: ADK.Types.Content.t(),
          author: String.t() | nil,
          timestamp: DateTime.t() | nil
        }

  defstruct [:content, :author, :timestamp]
end
