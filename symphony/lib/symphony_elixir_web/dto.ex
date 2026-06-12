defmodule SymphonyElixirWeb.DTO do
  @moduledoc false

  @spec issue(map()) :: map()
  def issue(issue) do
    %{
      id: issue.id,
      iid: issue.iid,
      identifier: issue.identifier,
      gitlabIssueId: issue.gitlab_issue_id,
      gitlabProjectId: issue.gitlab_project_id,
      webUrl: issue.web_url,
      title: issue.title,
      description: issue.description,
      descriptionPreview: issue.description_preview,
      gitlabState: issue.gitlab_state,
      workflowStatus: issue.workflow_status,
      priority: issue.priority,
      labels: issue.labels || [],
      assignees: issue.assignees || [],
      blockers: issue.blockers || [],
      blockedByCount: issue.blocked_by_count || 0,
      activeRunId: issue.active_run_id,
      lastRunStatus: issue.last_run_status,
      updatedAt: iso(issue.updated_at),
      gitlabUpdatedAt: iso(issue.gitlab_updated_at),
      lastSyncAt: iso(issue.last_synced_at)
    }
  end

  @spec run(map()) :: map()
  def run(run) do
    issue = run[:issue] || %{}

    %{
      id: run.id,
      issueId: run.gitlab_issue_id,
      issueIdentifier: run[:issue_identifier] || issue[:identifier],
      issueTitle: run[:issue_title] || issue[:title],
      issueWebUrl: run[:issue_web_url] || issue[:web_url],
      runNumber: run.run_number,
      status: run.status,
      mode: run.mode,
      workspacePath: run.workspace_path,
      codexThreadId: run.codex_thread_id,
      startedAt: iso(run.started_at),
      finishedAt: iso(run.finished_at),
      lastHeartbeatAt: iso(run.last_heartbeat_at),
      exitReason: run.exit_reason,
      errorMessage: run.error_message,
      blockedReason: run.blocked_reason,
      needsOperatorInput: run.needs_operator_input,
      summary: run.summary
    }
  end

  @spec block(map()) :: map()
  def block(block) do
    issue = block[:issue] || %{}

    %{
      id: block.id,
      issueId: block.gitlab_issue_id,
      issueIdentifier: block[:issue_identifier] || issue[:identifier],
      issueTitle: block[:issue_title] || issue[:title],
      issueWebUrl: block[:issue_web_url] || issue[:web_url],
      agentRunId: block.agent_run_id,
      blockType: block.block_type,
      message: block.message,
      payload: block.payload || %{},
      resolvedAt: iso(block.resolved_at),
      insertedAt: iso(block.inserted_at),
      updatedAt: iso(block.updated_at)
    }
  end

  @spec event(map()) :: map()
  def event(event) do
    %{
      id: event.id,
      issueId: event.gitlab_issue_id,
      eventType: event.event_type,
      source: event.source,
      actor: event.actor,
      payload: event.payload || %{},
      runId: event[:run_id],
      insertedAt: iso(event.inserted_at)
    }
  end

  defp iso(%DateTime{} = datetime), do: datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp iso(%Date{} = date), do: Date.to_iso8601(date)
  defp iso(value) when is_binary(value), do: value
  defp iso(_value), do: nil
end
