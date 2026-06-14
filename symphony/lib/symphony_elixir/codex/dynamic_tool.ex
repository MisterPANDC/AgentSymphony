defmodule SymphonyElixir.Codex.DynamicTool do
  @moduledoc """
  Executes narrow GitLab-scoped client-side tool calls requested by Codex.
  """

  alias SymphonyElixir.{Store, Sync.Poller, Tracker}
  alias SymphonyElixir.Persistence.WorkflowState

  @current_issue_tool "gitlab_current_issue"
  @get_notes_tool "get_current_issue_notes"
  @create_note_tool "create_current_issue_note"
  @update_state_tool "update_current_issue_state"
  @create_followup_tool "create_followup_issue"

  @spec execute(String.t() | nil, term(), keyword()) :: map()
  def execute(tool, arguments, opts \\ []) do
    case tool do
      @current_issue_tool -> current_issue_response(opts)
      @get_notes_tool -> current_issue_notes_response(opts)
      @create_note_tool -> create_current_issue_note(arguments, opts)
      @update_state_tool -> update_current_issue_state(arguments, opts)
      @create_followup_tool -> create_followup_issue(arguments, opts)
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
              "enum" => WorkflowState.statuses()
            },
            "reason" => %{"type" => ["string", "null"]}
          }
        }
      },
      %{
        "name" => @create_followup_tool,
        "description" => "Create a scoped GitLab follow-up issue for out-of-scope work discovered while handling the current issue. The new issue is initialized in Symphony as triage.",
        "inputSchema" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["title", "description", "acceptance_criteria"],
          "properties" => %{
            "title" => %{"type" => "string", "description" => "Clear title for the follow-up issue."},
            "description" => %{"type" => "string", "description" => "Follow-up issue body without expanding current issue scope."},
            "acceptance_criteria" => %{
              "type" => ["string", "array"],
              "description" => "Concrete completion criteria for the follow-up issue.",
              "items" => %{"type" => "string"}
            },
            "labels" => %{"type" => "array", "items" => %{"type" => "string"}},
            "assignee_ids" => %{"type" => "array", "items" => %{"type" => "integer"}},
            "milestone_id" => %{"type" => ["integer", "null"]},
            "due_date" => %{"type" => ["string", "null"], "description" => "ISO-8601 date, YYYY-MM-DD."},
            "confidential" => %{"type" => ["boolean", "null"]},
            "related_to_current_issue" => %{
              "type" => ["boolean", "null"],
              "description" => "Defaults to true. Creates a local related relation and links back to the current issue."
            },
            "blocked_by_current_issue" => %{
              "type" => ["boolean", "null"],
              "description" => "When true, the current issue blocks the new follow-up issue."
            }
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
         %{} = issue <- Store.get_issue(issue_id) || {:error, :issue_not_found},
         {:ok, status, reason} <- workflow_status(arguments),
         {:ok, workflow} <-
           Store.transition_workflow(issue_id, status,
             source: "agent",
             actor: "agent",
             reason: reason || "agent tool update"
           ),
         :ok <- Tracker.sync_issue_lifecycle(issue_id, issue.workflow_status, status) do
      success_response(%{workflow: workflow})
    else
      {:error, reason} -> failure_response(%{error: %{message: inspect(reason)}})
    end
  end

  defp create_followup_issue(arguments, opts) do
    with {:ok, issue_id} <- current_issue_id(opts),
         {:ok, attrs} <- followup_attrs(arguments),
         {:ok, result} <- Tracker.create_followup_issue(issue_id, attrs) do
      success_response(result)
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

  defp followup_attrs(arguments) when is_map(arguments) do
    attrs = %{
      title: argument_value(arguments, "title"),
      description: argument_value(arguments, "description"),
      acceptance_criteria: argument_value(arguments, "acceptance_criteria"),
      labels: argument_value(arguments, "labels"),
      assignee_ids: argument_value(arguments, "assignee_ids"),
      milestone_id: argument_value(arguments, "milestone_id"),
      due_date: argument_value(arguments, "due_date"),
      confidential: argument_value(arguments, "confidential"),
      related_to_current_issue: argument_value(arguments, "related_to_current_issue"),
      blocked_by_current_issue: argument_value(arguments, "blocked_by_current_issue")
    }

    with :ok <- require_nonempty(attrs.title, :title),
         :ok <- require_nonempty(attrs.description, :description),
         :ok <- require_acceptance_criteria(attrs.acceptance_criteria) do
      {:ok, attrs}
    end
  end

  defp followup_attrs(_arguments), do: {:error, :invalid_followup_arguments}

  defp argument_value(arguments, key) do
    Map.get(arguments, key, Map.get(arguments, String.to_atom(key)))
  end

  defp require_nonempty(value, field) when is_binary(value) do
    if String.trim(value) == "", do: {:error, {:missing_required_followup_field, field}}, else: :ok
  end

  defp require_nonempty(_value, field), do: {:error, {:missing_required_followup_field, field}}

  defp require_acceptance_criteria(value) when is_binary(value), do: require_nonempty(value, :acceptance_criteria)

  defp require_acceptance_criteria(value) when is_list(value) do
    if Enum.any?(value, &(is_binary(&1) and String.trim(&1) != "")) do
      :ok
    else
      {:error, {:missing_required_followup_field, :acceptance_criteria}}
    end
  end

  defp require_acceptance_criteria(_value), do: {:error, {:missing_required_followup_field, :acceptance_criteria}}

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
