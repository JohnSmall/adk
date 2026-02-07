defmodule ADK.RunConfig do
  @moduledoc """
  Runtime configuration for agent execution.
  """

  @type streaming_mode :: :none | :sse

  @type t :: %__MODULE__{
          streaming_mode: streaming_mode(),
          save_input_blobs_as_artifacts: boolean()
        }

  defstruct streaming_mode: :none,
            save_input_blobs_as_artifacts: false
end
