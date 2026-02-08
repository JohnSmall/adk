defmodule ADK.Tool.LoadMemory do
  @moduledoc """
  A tool that searches memory for relevant past interactions.

  When called by an LLM, searches the configured memory service
  for entries matching the provided query string.
  """

  @behaviour ADK.Tool

  alias ADK.Tool.Context, as: ToolContext

  @type t :: %__MODULE__{}

  defstruct []

  @impl ADK.Tool
  def name(%__MODULE__{}), do: "load_memory"

  @impl ADK.Tool
  def description(%__MODULE__{}),
    do: "Search memory for relevant information from past interactions."

  @impl ADK.Tool
  def declaration(%__MODULE__{}) do
    %{
      "name" => "load_memory",
      "description" => "Search memory for relevant information from past interactions.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "The search query to find relevant memories."
          }
        },
        "required" => ["query"]
      }
    }
  end

  @impl ADK.Tool
  def run(%__MODULE__{}, %ToolContext{} = ctx, args) do
    query = Map.get(args, "query", "")

    {:ok, entries} = ToolContext.search_memory(ctx, query)

    memories =
      Enum.map(entries, fn entry ->
        text = extract_text(entry.content)
        %{"author" => entry.author, "text" => text}
      end)

    {:ok, %{"memories" => memories}}
  end

  defp extract_text(%ADK.Types.Content{parts: parts}) do
    parts
    |> Enum.flat_map(fn part ->
      if is_binary(part.text), do: [part.text], else: []
    end)
    |> Enum.join("\n")
  end

  defp extract_text(_), do: ""
end
