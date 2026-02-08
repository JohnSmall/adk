defmodule ADK.Tool.LoadArtifacts do
  @moduledoc """
  A tool that loads artifacts by name from the artifact service.

  When called by an LLM, loads the latest version of each
  requested artifact and returns their content.
  """

  @behaviour ADK.Tool

  alias ADK.Tool.Context, as: ToolContext

  @type t :: %__MODULE__{}

  defstruct []

  @impl ADK.Tool
  def name(%__MODULE__{}), do: "load_artifacts"

  @impl ADK.Tool
  def description(%__MODULE__{}),
    do: "Load artifacts by name to retrieve their content."

  @impl ADK.Tool
  def declaration(%__MODULE__{}) do
    %{
      "name" => "load_artifacts",
      "description" => "Load artifacts by name to retrieve their content.",
      "parameters" => %{
        "type" => "object",
        "properties" => %{
          "artifact_names" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "List of artifact filenames to load."
          }
        },
        "required" => ["artifact_names"]
      }
    }
  end

  @impl ADK.Tool
  def run(%__MODULE__{}, %ToolContext{} = ctx, args) do
    names = Map.get(args, "artifact_names", [])

    artifacts =
      Enum.map(names, fn name ->
        case ToolContext.load_artifact(ctx, name) do
          {:ok, part} ->
            %{"filename" => name, "content" => part_to_content(part)}

          {:error, reason} ->
            %{"filename" => name, "error" => to_string(reason)}
        end
      end)

    {:ok, %{"artifacts" => artifacts}}
  end

  defp part_to_content(%{text: text}) when is_binary(text), do: text

  defp part_to_content(%{inline_data: %{mime_type: mime}}) when is_binary(mime),
    do: "[binary data: #{mime}]"

  defp part_to_content(_), do: "[unknown content]"
end
