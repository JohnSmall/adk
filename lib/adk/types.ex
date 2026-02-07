defmodule ADK.Types.Blob do
  @moduledoc "Binary data with MIME type."
  @type t :: %__MODULE__{
          data: binary(),
          mime_type: String.t()
        }

  @enforce_keys [:data, :mime_type]
  defstruct [:data, :mime_type]
end

defmodule ADK.Types.FunctionCall do
  @moduledoc "Represents a function call request from an LLM."
  @type t :: %__MODULE__{
          name: String.t(),
          id: String.t() | nil,
          args: map()
        }

  @enforce_keys [:name]
  defstruct [:name, :id, args: %{}]
end

defmodule ADK.Types.FunctionResponse do
  @moduledoc "Represents a function call response."
  @type t :: %__MODULE__{
          name: String.t(),
          id: String.t() | nil,
          response: map()
        }

  @enforce_keys [:name]
  defstruct [:name, :id, response: %{}]
end

defmodule ADK.Types.Part do
  @moduledoc """
  A single part of a Content message.

  Parts use a tagged-union style: exactly one of `text`, `function_call`,
  `function_response`, or `inline_data` should be set.
  """

  alias ADK.Types.{Blob, FunctionCall, FunctionResponse}

  @type t :: %__MODULE__{
          text: String.t() | nil,
          function_call: FunctionCall.t() | nil,
          function_response: FunctionResponse.t() | nil,
          inline_data: Blob.t() | nil,
          thought: boolean()
        }

  defstruct [:text, :function_call, :function_response, :inline_data, thought: false]

  @spec new_text(String.t()) :: t()
  def new_text(text), do: %__MODULE__{text: text}

  @spec new_function_call(FunctionCall.t()) :: t()
  def new_function_call(%FunctionCall{} = fc), do: %__MODULE__{function_call: fc}

  @spec new_function_response(FunctionResponse.t()) :: t()
  def new_function_response(%FunctionResponse{} = fr), do: %__MODULE__{function_response: fr}

  @spec new_inline_data(binary(), String.t()) :: t()
  def new_inline_data(data, mime_type) do
    %__MODULE__{inline_data: %Blob{data: data, mime_type: mime_type}}
  end

  @spec function_call?(t()) :: boolean()
  def function_call?(%__MODULE__{function_call: nil}), do: false
  def function_call?(%__MODULE__{function_call: _}), do: true

  @spec function_response?(t()) :: boolean()
  def function_response?(%__MODULE__{function_response: nil}), do: false
  def function_response?(%__MODULE__{function_response: _}), do: true
end

defmodule ADK.Types.Content do
  @moduledoc "A message containing one or more parts with a role."

  alias ADK.Types.Part

  @type t :: %__MODULE__{
          role: String.t(),
          parts: [Part.t()]
        }

  @enforce_keys [:role, :parts]
  defstruct [:role, :parts]

  @spec new_from_text(String.t(), String.t()) :: t()
  def new_from_text(role, text) do
    %__MODULE__{role: role, parts: [Part.new_text(text)]}
  end

  @spec new_from_bytes(String.t(), binary(), String.t()) :: t()
  def new_from_bytes(role, data, mime_type) do
    %__MODULE__{role: role, parts: [Part.new_inline_data(data, mime_type)]}
  end
end

defmodule ADK.Types do
  @moduledoc """
  Core content types equivalent to Google's genai SDK types.

  Provides Content, Part, FunctionCall, FunctionResponse, and Blob
  structs used throughout the ADK for representing LLM interactions.
  """

  alias ADK.Types.{Content, FunctionCall, FunctionResponse, Part}

  @role_user "user"
  @role_model "model"

  def role_user, do: @role_user
  def role_model, do: @role_model

  @doc "Extracts all function calls from a Content struct."
  @spec function_calls(Content.t()) :: [FunctionCall.t()]
  def function_calls(%Content{parts: parts}) do
    Enum.flat_map(parts, fn part ->
      if Part.function_call?(part), do: [part.function_call], else: []
    end)
  end

  @doc "Extracts all function responses from a Content struct."
  @spec function_responses(Content.t()) :: [FunctionResponse.t()]
  def function_responses(%Content{parts: parts}) do
    Enum.flat_map(parts, fn part ->
      if Part.function_response?(part), do: [part.function_response], else: []
    end)
  end

  @doc "Returns true if the content contains any function calls."
  @spec has_function_calls?(Content.t()) :: boolean()
  def has_function_calls?(%Content{parts: parts}) do
    Enum.any?(parts, &Part.function_call?/1)
  end

  @doc "Returns true if the content contains any function responses."
  @spec has_function_responses?(Content.t()) :: boolean()
  def has_function_responses?(%Content{parts: parts}) do
    Enum.any?(parts, &Part.function_response?/1)
  end
end
