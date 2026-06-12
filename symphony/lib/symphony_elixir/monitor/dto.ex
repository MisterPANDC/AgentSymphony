defmodule SymphonyElixir.Monitor.DTO do
  @moduledoc """
  DTO builders for the React Run Monitor and operational JSON APIs.
  """

  alias Symphony.GitLab.Config, as: GitLabConfig
  alias SymphonyElixir.{Config, Orchestrator, Store, Sync.Poller}

  @spec state(timeout()) :: map()
  def state(snapshot_timeout_ms \\ 15_000) do
    store = Store.snapshot()
    orchestrator = Orchestrator.snapshot(Orchestrator, snapshot_timeout_ms)
    sync_status = Poller.status()
    gitlab_config = load_gitlab_config()
    workflow = load_workflow_status()

    %{
      runtime: runtime_dto(workflow, gitlab_config),
      gitlab: gitlab_dto(gitlab_config, store.project),
      sync: sync_dto(sync_status),
      agents: agents_dto(store, orchestrator),
      activeRuns: active_runs_dto(store, orchestrator),
      blocked: blocked_dto(store, orchestrator),
      recentEvents: recent_events_dto(store)
    }
  end

  @spec v1_state(timeout()) :: map()
  def v1_state(snapshot_timeout_ms \\ 15_000) do
    monitor = state(snapshot_timeout_ms)

    %{
      generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
      monitor: monitor,
      running: monitor.activeRuns,
      blocked: monitor.blocked,
      counts: %{
        running: monitor.agents.running,
        queued: monitor.agents.queued,
        blocked: monitor.agents.blocked
      }
    }
  end

  @spec issue_debug(String.t(), timeout()) :: {:ok, map()} | {:error, :issue_not_found}
  def issue_debug(identifier, snapshot_timeout_ms \\ 15_000) do
    case Store.get_issue_by_identifier(identifier) || Store.get_issue_by_iid(identifier) do
      nil ->
        {:error, :issue_not_found}

      issue ->
        runs = Store.list_runs(issue_id: issue.id)

        {:ok,
         %{
           issue: issue_dto(issue),
           notes: Store.list_notes(issue.id),
           events: Store.list_events(issue_id: issue.id),
           runs: Enum.map(runs, &run_dto/1),
           monitor: state(snapshot_timeout_ms)
         }}
    end
  end

  defp runtime_dto(workflow, gitlab_config) do
    settings = safe_settings()
    endpoint_port = SymphonyElixir.HttpServer.bound_port() || (gitlab_config && gitlab_config.port) || 4000

    %{
      mode: "local_single_user",
      appVersion: app_version(),
      uptimeSeconds: uptime_seconds(),
      bindHost: (gitlab_config && gitlab_config.bind_host) || settings.server.host,
      port: endpoint_port,
      workflowPath: SymphonyElixir.Workflow.workflow_file_path(),
      workflowLoaded: workflow.loaded,
      workflowLastLoadedAt: workflow.loaded_at,
      workflowLastError: workflow.error
    }
  end

  defp gitlab_dto(config, project) do
    %{
      apiRoot: (config && config.gitlab_api_root) || project_value(project, :api_root),
      projectRef: (config && config.gitlab_project_ref) || project_value(project, :project_ref),
      projectId: project_value(project, :project_id),
      projectName: project_value(project, :name),
      projectWebUrl: project_value(project, :web_url),
      readOnly: project_value(project, :read_only) == true,
      lastValidationAt: iso(project_value(project, :last_validated_at)),
      lastValidationError: project_value(project, :last_validation_error)
    }
  end

  defp sync_dto(status) do
    cursors = status.cursors || %{}
    issue_cursor = Map.get(cursors, "gitlab:gitlab_issues_updated_after", %{})
    notes_cursor = Map.get(cursors, "gitlab:gitlab_notes_last_full_sync_at", %{})

    %{
      issueLastSuccessAt: iso(issue_cursor[:last_success_at]),
      issueLastAttemptAt: iso(issue_cursor[:last_attempt_at]),
      issueLastError: issue_cursor[:last_error] || status.last_error,
      notesLastSuccessAt: iso(notes_cursor[:last_success_at]),
      pending: status.pending == true,
      nextRunAt: iso(status.next_run_at)
    }
  end

  defp agents_dto(store, orchestrator) do
    runs = store.runs || []
    running_count = if is_map(orchestrator), do: length(Map.get(orchestrator, :running, [])), else: 0

    %{
      maxConcurrent: safe_settings().agent.max_concurrent_agents,
      queued: Enum.count(runs, &(&1.status == "queued")),
      starting: Enum.count(runs, &(&1.status == "starting")),
      running: max(Enum.count(runs, &(&1.status == "running")), running_count),
      blocked: Enum.count(runs, &(&1.status == "blocked")) + length(store.open_runtime_blocks || []),
      succeededRecent: Enum.count(runs, &(&1.status == "succeeded")),
      failedRecent: Enum.count(runs, &(&1.status == "failed"))
    }
  end

  defp active_runs_dto(store, orchestrator) do
    persisted =
      store.runs
      |> Enum.filter(&(&1.status in ["queued", "starting", "running", "blocked"]))
      |> Enum.map(&run_dto/1)

    runtime =
      case orchestrator do
        %{running: running} when is_list(running) -> Enum.map(running, &runtime_run_dto/1)
        _ -> []
      end

    dedupe_by_id(persisted ++ runtime)
  end

  defp blocked_dto(store, orchestrator) do
    persisted = Enum.map(store.open_runtime_blocks || [], &block_dto/1)

    runtime =
      case orchestrator do
        %{blocked: blocked} when is_list(blocked) -> Enum.map(blocked, &runtime_block_dto/1)
        _ -> []
      end

    dedupe_by_id(persisted ++ runtime)
  end

  defp recent_events_dto(store) do
    store.events
    |> Enum.take(30)
    |> Enum.map(fn event ->
      issue =
        case event.gitlab_issue_id do
          nil -> nil
          issue_id -> Store.get_issue(issue_id)
        end

      %{
        id: event.id,
        type: event.event_type,
        message: event.payload[:message] || event.payload["message"],
        insertedAt: iso(event.inserted_at),
        issueIdentifier: issue && issue.identifier,
        runId: event[:run_id]
      }
    end)
  end

  defp issue_dto(issue) do
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

  defp run_dto(run) do
    issue = run[:issue] || %{}

    %{
      id: run.id,
      issueId: run.gitlab_issue_id,
      issueIdentifier: run[:issue_identifier] || issue[:identifier],
      issueTitle: run[:issue_title] || issue[:title],
      issueWebUrl: run[:issue_web_url] || issue[:web_url],
      runNumber: run.run_number,
      status: run.status,
      workspacePath: run.workspace_path,
      startedAt: iso(run.started_at),
      finishedAt: iso(run.finished_at),
      lastHeartbeatAt: iso(run.last_heartbeat_at),
      currentTurn: nil,
      exitReason: run.exit_reason,
      errorMessage: run.error_message
    }
  end

  defp runtime_run_dto(row) do
    %{
      id: row.session_id || row.issue_id,
      issueId: row.issue_id,
      issueIdentifier: row.identifier,
      issueTitle: nil,
      issueWebUrl: row[:issue_url],
      runNumber: 0,
      status: "running",
      workspacePath: row[:workspace_path],
      startedAt: iso(row[:started_at]),
      finishedAt: nil,
      lastHeartbeatAt: iso(row[:last_codex_timestamp]),
      currentTurn: row[:turn_count],
      exitReason: nil,
      errorMessage: nil
    }
  end

  defp block_dto(block) do
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
      insertedAt: iso(block.inserted_at)
    }
  end

  defp runtime_block_dto(row) do
    %{
      id: row.session_id || row.issue_id,
      issueId: row.issue_id,
      issueIdentifier: row.identifier,
      issueTitle: nil,
      issueWebUrl: row[:issue_url],
      agentRunId: nil,
      blockType: "operator_input",
      message: row.error,
      insertedAt: iso(row[:blocked_at])
    }
  end

  defp load_gitlab_config do
    case GitLabConfig.load() do
      {:ok, config} -> config
      _ -> nil
    end
  end

  defp load_workflow_status do
    case SymphonyElixir.Workflow.current() do
      {:ok, _workflow} ->
        %{loaded: true, loaded_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(), error: nil}

      {:error, reason} ->
        %{loaded: false, loaded_at: nil, error: inspect(reason)}
    end
  end

  defp safe_settings do
    Config.settings!()
  rescue
    _ ->
      %{
        agent: %{max_concurrent_agents: 10},
        server: %{host: "127.0.0.1"}
      }
  end

  defp app_version do
    case Application.spec(:symphony_elixir, :vsn) do
      nil -> nil
      vsn -> to_string(vsn)
    end
  end

  defp uptime_seconds do
    Store.snapshot().started_at
    |> case do
      %DateTime{} = started_at -> max(DateTime.diff(DateTime.utc_now(), started_at, :second), 0)
      _ -> 0
    end
  end

  defp project_value(nil, _key), do: nil
  defp project_value(project, key), do: project[key] || project[to_string(key)]

  defp dedupe_by_id(rows) do
    rows
    |> Enum.reduce({MapSet.new(), []}, fn row, {seen, acc} ->
      id = row.id

      if MapSet.member?(seen, id) do
        {seen, acc}
      else
        {MapSet.put(seen, id), [row | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp iso(%DateTime{} = datetime), do: datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()
  defp iso(nil), do: nil
  defp iso(value) when is_binary(value), do: value
  defp iso(_value), do: nil
end
