defmodule SymphonyElixirWeb.DTO do
  @moduledoc false

  @spec issue(map(), keyword()) :: map()
  def issue(issue, opts \\ []) do
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
      mergeRequestCount: Keyword.get(opts, :merge_request_count),
      activeRunId: issue.active_run_id,
      lastRunStatus: issue.last_run_status,
      updatedAt: iso(issue.updated_at),
      gitlabUpdatedAt: iso(issue.gitlab_updated_at),
      lastSyncAt: iso(issue.last_synced_at)
    }
  end

  @spec merge_request(map()) :: map()
  def merge_request(%{} = merge_request) do
    %{
      id: value(merge_request, :merge_request_id) || value(merge_request, :id),
      iid: value(merge_request, :iid),
      title: value(merge_request, :title) || "(untitled)",
      description: value(merge_request, :description),
      state: value(merge_request, :state),
      draft: value(merge_request, :draft) || value(merge_request, :work_in_progress) || false,
      workInProgress: value(merge_request, :work_in_progress) || false,
      webUrl: value(merge_request, :web_url),
      sourceBranch: value(merge_request, :source_branch),
      targetBranch: value(merge_request, :target_branch),
      mergeStatus: value(merge_request, :merge_status),
      detailedMergeStatus: value(merge_request, :detailed_merge_status),
      createdAt: iso(value(merge_request, :gitlab_created_at) || value(merge_request, :created_at)),
      updatedAt: iso(value(merge_request, :gitlab_updated_at) || value(merge_request, :updated_at)),
      mergedAt: iso(value(merge_request, :merged_at)),
      closedAt: iso(value(merge_request, :closed_at)),
      labels: labels(value(merge_request, :labels)),
      author: user(value(merge_request, :author)),
      assignees: users(value(merge_request, :assignees)),
      reviewers: users(value(merge_request, :reviewers)),
      milestone: milestone(value(merge_request, :milestone)),
      userNotesCount: value(merge_request, :user_notes_count),
      upvotes: value(merge_request, :upvotes),
      downvotes: value(merge_request, :downvotes),
      changesCount: value(merge_request, :changes_count),
      references: value(merge_request, :references) || %{},
      headPipeline: pipeline(value(merge_request, :head_pipeline) || value(merge_request, :pipeline)),
      raw: %{
        "should_remove_source_branch" => raw_value(merge_request, "should_remove_source_branch"),
        "force_remove_source_branch" => raw_value(merge_request, "force_remove_source_branch"),
        "squash" => raw_value(merge_request, "squash"),
        "has_conflicts" => raw_value(merge_request, "has_conflicts"),
        "blocking_discussions_resolved" => raw_value(merge_request, "blocking_discussions_resolved")
      }
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

  defp value(map, key) when is_atom(key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp raw_value(map, key) do
    case value(map, :raw_gitlab) do
      %{} = raw -> Map.get(raw, key) || Map.get(raw, String.to_atom(key))
      _ -> Map.get(map, key) || Map.get(map, String.to_atom(key))
    end
  end

  defp labels(labels) when is_list(labels), do: Enum.map(labels, &to_string/1)
  defp labels(_labels), do: []

  defp users(users) when is_list(users), do: users |> Enum.map(&user/1) |> Enum.reject(&is_nil/1)
  defp users(_users), do: []

  defp user(%{} = user) do
    %{
      id: user["id"] || user[:id],
      username: user["username"] || user[:username],
      name: user["name"] || user[:name],
      avatarUrl: user["avatar_url"] || user["avatarUrl"] || user[:avatar_url] || user[:avatarUrl],
      webUrl: user["web_url"] || user["webUrl"] || user[:web_url] || user[:webUrl]
    }
  end

  defp user(_user), do: nil

  defp milestone(%{} = milestone) do
    %{
      id: milestone["id"] || milestone[:id],
      iid: milestone["iid"] || milestone[:iid],
      title: milestone["title"] || milestone[:title],
      state: milestone["state"] || milestone[:state],
      dueDate: milestone["due_date"] || milestone["dueDate"] || milestone[:due_date] || milestone[:dueDate]
    }
  end

  defp milestone(_milestone), do: nil

  defp pipeline(%{} = pipeline) do
    %{
      id: pipeline["id"] || pipeline[:id],
      status: pipeline["status"] || pipeline[:status],
      ref: pipeline["ref"] || pipeline[:ref],
      webUrl: pipeline["web_url"] || pipeline["webUrl"] || pipeline[:web_url] || pipeline[:webUrl],
      updatedAt: iso(pipeline["updated_at"] || pipeline["updatedAt"] || pipeline[:updated_at] || pipeline[:updatedAt])
    }
  end

  defp pipeline(_pipeline), do: nil

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
