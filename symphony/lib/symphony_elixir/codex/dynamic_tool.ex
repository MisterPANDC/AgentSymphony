defmodule SymphonyElixir.Codex.DynamicTool do
  @moduledoc """
  Executes narrow GitLab-scoped client-side tool calls requested by Codex.
  """

  alias SymphonyElixir.{Store, Sync.Poller, Tracker}

  @current_issue_tool "gitlab_current_issue"
  @get_notes_tool "get_current_issue_notes"
  @create_note_tool "create_current_issue_note"
  @update_state_tool "update_current_issue_state"

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    case tool do
      @current_issue_tool -> current_issue_response(opts)
      @get_notes_tool -> current_issue_notes_response(opts)
      @create_note_tool -> create_current_issue_note(arguments, opts)
      @update_state_tool -> update_current_issue_state(arguments, opts)
      other -> unsupported_tool_response(other)
    end
  end

  @spec tool_specs() :: [map()]
  def tool_specs do
    [
      %{
        "name" => @current_issue_tool,
        "description" => "Return the current GitLab issue and Symphony workflow state.",
        "inputSchema" => empty_schema()
      },
      %{
        "name" => @get_notes_tool,
        "description" => "Return notes for the current GitLab issue after syncing them through Symphony.",
        "inputSchema" => empty_schema()
      },
      %{
        "name" => @create_note_tool,
        "description" => "Create a GitLab note on the current issue through Symphony's backend.",
        "inputSchema" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["body"],
          "properties" => %{
            "body" => %{"type" => "string", "description" => "Note body to post to the current GitLab issue."}
          }
        }
      },
      %{
        "name" => @update_state_tool,
        "description" => "Update Symphony's internal workflow status for the current issue.",
        "inputSchema" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["status"],
          "properties" => %{
            "status" => %{
              "type" => "string",
              "enum" => ["triage", "todo", "in_progress", "blocked", "review", "done", "canceled"]
            },
            "reason" => %{"type" => ["string", "null"]}
          }
        }
      }
    ]
  end

  defp current_issue_response(opts) do
    with {:ok, issue_id} <- current_issue_id(opts),
         %{} = issue <- Store.get_issue(issue_id) do
      success_response(%{issue: issue})
    else
      nil -> failure_response(%{error: %{message: "Current GitLab issue was not found."}})
      {:error, reason} -> failure_response(%{error: %{message: inspect(reason)}})
    end
  end

  defp current_issue_notes_response(opts) do
    with {:ok, issue_id} <- current_issue_id(opts) do
      Poller.sync_issue_notes(issue_id)
      success_response(%{notes: Store.list_notes(issue_id)})
    else
      {:error, reason} -> failure_response(%{error: %{message: inspect(reason)}})
    end
  end

  defp create_current_issue_note(arguments, opts) do
    with {:ok, issue_id} <- current_issue_id(opts),
         {:ok, body} <- note_body(arguments),
         :ok <- Tracker.create_comment(issue_id, body) do
      success_response(%{created: true, notes: Store.list_notes(issue_id)})
    else
      {:error, reason} -> failure_response(%{error: %{message: inspect(reason)}})
    end
  end

  defp update_current_issue_state(arguments, opts) do
    with {:ok, issue_id} <- current_issue_id(opts),
         {:ok, status, reason} <- workflow_status(arguments),
         {:ok, workflow} <-
           Store.transition_workflow(issue_id, status,
             source: "agent",
             actor: "agent",
             reason: reason || "agent tool update"
           ) do
      success_response(%{workflow: workflow})
    else
      {:error, reason} -> failure_response(%{error: %{message: inspect(reason)}})
    end
  end

  defp current_issue_id(opts) do
    case Keyword.get(opts, :current_issue) do
      %{id: issue_id} when is_binary(issue_id) -> {:ok, issue_id}
      %{"id" => issue_id} when is_binary(issue_id) -> {:ok, issue_id}
      _ -> {:error, :missing_current_issue}
    end
  end

  defp note_body(%{"body" => body}) when is_binary(body) and byte_size(body) > 0, do: {:ok, body}
  defp note_body(%{body: body}) when is_binary(body) and byte_size(body) > 0, do: {:ok, body}
  defp note_body(_arguments), do: {:error, :missing_note_body}

  defp workflow_status(%{"status" => status} = args) when is_binary(status) do
    {:ok, status, args["reason"]}
  end

  defp workflow_status(%{status: status} = args) when is_binary(status) do
    {:ok, status, Map.get(args, :reason)}
  end

  defp workflow_status(_arguments), do: {:error, :missing_workflow_status}

  defp unsupported_tool_response(other) do
    failure_response(%{
      error: %{
        message: "Unsupported dynamic tool: #{inspect(other)}.",
        supportedTools: supported_tool_names()
      }
    })
  end

  defp success_response(payload), do: dynamic_tool_response(true, payload)
  defp failure_response(payload), do: dynamic_tool_response(false, payload)

  defp dynamic_tool_response(success, payload) when is_boolean(success) do
    output = Jason.encode!(payload, pretty: true)

    %{
      "success" => success,
      "output" => output,
      "contentItems" => [%{"type" => "inputText", "text" => output}]
    }
  end

  defp supported_tool_names, do: Enum.map(tool_specs(), & &1["name"])

  defp empty_schema do
    %{"type" => "object", "additionalProperties" => false, "properties" => %{}}
  end
end
