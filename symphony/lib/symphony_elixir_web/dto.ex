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
      blockers: (issue.blockers || []) |> Enum.map(&issue_ref/1),
      relations: relations(issue.relations || %{}),
      isBlocked: issue.is_blocked || false,
      unresolvedBlockerCount: issue.unresolved_blocker_count || 0,
      openRuntimeBlockCount: issue.open_runtime_block_count || 0,
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

  @spec issue_ref(map()) :: map()
  def issue_ref(ref) when is_map(ref) do
    %{
      issueId: ref[:issue_id] || ref["issue_id"] || ref[:id] || ref["id"],
      iid: ref[:iid] || ref["iid"],
      identifier: ref[:identifier] || ref["identifier"],
      title: ref[:title] || ref["title"],
      status: ref[:status] || ref["status"],
      reason: ref[:reason] || ref["reason"],
      relationType: ref[:relation_type] || ref["relation_type"],
      direction: ref[:direction] || ref["direction"]
    }
  end

  defp iso(%DateTime{} = datetime), do: datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp iso(%Date{} = date), do: Date.to_iso8601(date)
  defp iso(value) when is_binary(value), do: value
  defp iso(_value), do: nil

  defp relations(relations) do
    %{
      related: relations |> relation_items(:related) |> Enum.map(&issue_ref/1),
      blocks: relations |> relation_items(:blocks) |> Enum.map(&issue_ref/1),
      blockedBy: relations |> relation_items(:blocked_by) |> Enum.map(&issue_ref/1)
    }
  end

  defp relation_items(relations, key) when is_map(relations) do
    Map.get(relations, key) || Map.get(relations, to_string(key)) || []
  end
end
