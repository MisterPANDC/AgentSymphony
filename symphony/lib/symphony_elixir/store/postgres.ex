defmodule SymphonyElixir.Store.Postgres do
  @moduledoc """
  PostgreSQL-backed Store implementation for GitLab-backed Symphony.
  """

  use Agent

  import Ecto.Query

  alias SymphonyElixir.Persistence.AgentRun
  alias SymphonyElixir.Persistence.AgentRunEvent
  alias SymphonyElixir.Persistence.Issue
  alias SymphonyElixir.Persistence.IssueDependency
  alias SymphonyElixir.Persistence.IssueEvent
  alias SymphonyElixir.Persistence.IssueNote
  alias SymphonyElixir.Persistence.ProjectSetting
  alias SymphonyElixir.Persistence.RuntimeBlock
  alias SymphonyElixir.Persistence.SyncCursor
  alias SymphonyElixir.Persistence.WorkflowState
  alias SymphonyElixir.Repo
  alias SymphonyElixir.Tracker

  @workflow_statuses WorkflowState.statuses()
  @priorities WorkflowState.priorities()
  @block_types RuntimeBlock.block_types()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{started_at: now()} end, name: __MODULE__)
  end

  @spec upsert_project(map()) :: map()
  def upsert_project(attrs) do
    attrs =
      attrs
      |> atomize_keys()
      |> Map.put_new(:read_only, false)

    existing = Repo.one(from(p in ProjectSetting, order_by: [asc: p.inserted_at], limit: 1))

    (existing || %ProjectSetting{})
    |> ProjectSetting.changeset(attrs)
    |> Repo.insert_or_update!()
    |> plain()
  end

  @spec project() :: map() | nil
  def project do
    ProjectSetting
    |> order_by([p], asc: p.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> maybe_plain()
  end

  @spec upsert_issue(map()) :: map()
  def upsert_issue(attrs) do
    attrs = atomize_keys(attrs)
    project = current_project!()

    attrs =
      attrs
      |> Map.put(:gitlab_project_setting_id, project.id)
      |> Map.update(:labels, [], &(&1 || []))
      |> Map.update(:assignees, [], &(&1 || []))
      |> Map.put_new(:confidential, false)

    issue =
      Repo.one(
        from(i in Issue,
          where: i.gitlab_project_setting_id == ^project.id and i.iid == ^attrs.iid,
          limit: 1
        )
      )

    issue =
      (issue || %Issue{})
      |> Issue.changeset(attrs)
      |> Repo.insert_or_update!()

    ensure_workflow_state(issue.id, "triage", "synced from GitLab")
    append_event("gitlab_issue_synced", "gitlab_sync", %{iid: issue.iid, title: issue.title}, issue_id: issue.id)

    decorate_issue(issue)
  end

  @spec list_issues(keyword()) :: [map()]
  def list_issues(filters \\ []) do
    Issue
    |> order_by([i], desc: coalesce(i.gitlab_updated_at, i.updated_at), desc: i.iid)
    |> Repo.all()
    |> Enum.map(&decorate_issue/1)
    |> apply_issue_filters(filters)
  end

  @spec get_issue(String.t()) :: map() | nil
  def get_issue(id) do
    case Repo.get(Issue, id) do
      nil -> nil
      issue -> decorate_issue(issue)
    end
  end

  @spec get_issue_by_iid(integer() | String.t()) :: map() | nil
  def get_issue_by_iid(iid) do
    iid = parse_int(iid)

    query =
      from(i in Issue,
        order_by: [desc: i.updated_at],
        limit: 1
      )

    query = if iid, do: from(i in query, where: i.iid == ^iid), else: from(i in query, where: false)

    query
    |> Repo.one()
    |> maybe_decorate_issue()
  end

  @spec get_issue_by_identifier(String.t()) :: map() | nil
  def get_issue_by_identifier(identifier) when is_binary(identifier) do
    iid =
      cond do
        Regex.match?(~r/^GL-\d+$/i, identifier) ->
          identifier |> String.split("-", parts: 2) |> List.last() |> parse_int()

        String.contains?(identifier, "#") ->
          identifier |> String.split("#") |> List.last() |> parse_int()

        true ->
          parse_int(identifier)
      end

    get_issue_by_iid(iid)
  end

  def get_issue_by_identifier(_identifier), do: nil

  @spec issue_to_tracker(map()) :: Tracker.Issue.t()
  def issue_to_tracker(issue), do: tracker_issue(undecorate(issue))

  @spec list_candidate_tracker_issues([String.t()]) :: [Tracker.Issue.t()]
  def list_candidate_tracker_issues(required_labels) do
    list_issues(status: "todo", gitlab_state: "opened")
    |> Enum.reject(&unresolved_dependency?(&1.id))
    |> Enum.filter(&labels_satisfy?(&1.labels, required_labels))
    |> Enum.reject(&active_run_id(&1.id))
    |> Enum.map(&tracker_issue/1)
  end

  @spec tracker_issues_by_ids([String.t()]) :: [Tracker.Issue.t()]
  def tracker_issues_by_ids(issue_ids) do
    wanted = MapSet.new(issue_ids)

    Issue
    |> where([i], i.id in ^issue_ids)
    |> Repo.all()
    |> Enum.map(&decorate_issue/1)
    |> Enum.filter(&MapSet.member?(wanted, &1.id))
    |> Enum.map(&tracker_issue/1)
  end

  @spec tracker_issues_by_workflow_statuses([String.t()]) :: [Tracker.Issue.t()]
  def tracker_issues_by_workflow_statuses(statuses) do
    statuses = Enum.map(statuses, &normalize_status/1)

    from(i in Issue,
      join: w in WorkflowState,
      on: w.gitlab_issue_id == i.id,
      where: w.status in ^statuses,
      order_by: [desc: i.gitlab_updated_at]
    )
    |> Repo.all()
    |> Enum.map(&decorate_issue/1)
    |> Enum.map(&tracker_issue/1)
  end

  @spec transition_workflow(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def transition_workflow(issue_id, next_status, opts \\ []) do
    next_status = normalize_status(next_status)

    Repo.transaction(fn ->
      with true <- next_status in @workflow_statuses || {:error, :invalid_status},
           %Issue{} = issue <- Repo.get(Issue, issue_id) || {:error, :issue_not_found},
           %WorkflowState{} = workflow <- ensure_workflow_state(issue.id),
           true <- allowed_transition?(workflow.status, next_status) || {:error, :invalid_transition} do
        previous_status = workflow.status

        attrs = %{
          status: next_status,
          claimed_by: Keyword.get(opts, :claimed_by, workflow.claimed_by),
          claimed_at: Keyword.get(opts, :claimed_at, workflow.claimed_at),
          last_transition_at: now(),
          last_transition_reason: Keyword.get(opts, :reason)
        }

        workflow =
          workflow
          |> WorkflowState.changeset(attrs)
          |> Repo.update!()
          |> plain()

        append_event(
          "workflow_transitioned",
          Keyword.get(opts, :source, "local_ui"),
          %{
            from: previous_status,
            to: next_status,
            reason: Keyword.get(opts, :reason)
          },
          issue_id: issue_id,
          actor: Keyword.get(opts, :actor, "local_operator")
        )

        workflow
      else
        {:error, reason} -> Repo.rollback(reason)
        false -> Repo.rollback(:invalid_transition)
        nil -> Repo.rollback(:issue_not_found)
      end
    end)
    |> case do
      {:ok, workflow} -> {:ok, workflow}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec update_priority(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def update_priority(issue_id, priority) do
    priority = normalize_priority(priority)

    cond do
      priority not in @priorities ->
        {:error, :invalid_priority}

      is_nil(Repo.get(Issue, issue_id)) ->
        {:error, :issue_not_found}

      true ->
        workflow =
          issue_id
          |> ensure_workflow_state()
          |> WorkflowState.changeset(%{priority: priority})
          |> Repo.update!()
          |> plain()

        append_event("workflow_priority_changed", "local_ui", %{priority: priority}, issue_id: issue_id)
        {:ok, workflow}
    end
  end

  @spec list_blockers(String.t()) :: [map()]
  def list_blockers(issue_id), do: blocker_dtos(issue_id)

  @spec add_blocker(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add_blocker(blocked_issue_id, blocking_issue_id, opts \\ []) do
    cond do
      blocked_issue_id == blocking_issue_id ->
        {:error, :self_dependency}

      is_nil(Repo.get(Issue, blocked_issue_id)) or is_nil(Repo.get(Issue, blocking_issue_id)) ->
        {:error, :issue_not_found}

      dependency_path?(blocking_issue_id, blocked_issue_id) ->
        {:error, :dependency_cycle}

      true ->
        attrs = %{
          blocked_issue_id: blocked_issue_id,
          blocking_issue_id: blocking_issue_id,
          created_by: Keyword.get(opts, :actor, "local_operator"),
          reason: Keyword.get(opts, :reason)
        }

        edge =
          %IssueDependency{}
          |> IssueDependency.changeset(attrs)
          |> Repo.insert!(
            on_conflict: {:replace, [:reason, :created_by, :updated_at]},
            conflict_target: [:blocked_issue_id, :blocking_issue_id]
          )
          |> plain()

        append_event("dependency_added", "local_ui", Map.take(edge, [:blocking_issue_id, :reason]), issue_id: blocked_issue_id)
        {:ok, edge}
    end
  end

  @spec remove_blocker(String.t(), String.t()) :: :ok | {:error, term()}
  def remove_blocker(blocked_issue_id, blocking_issue_id) do
    case Repo.one(
           from(e in IssueDependency,
             where: e.blocked_issue_id == ^blocked_issue_id and e.blocking_issue_id == ^blocking_issue_id,
             limit: 1
           )
         ) do
      nil ->
        {:error, :dependency_not_found}

      edge ->
        Repo.delete!(edge)
        append_event("dependency_removed", "local_ui", %{blocking_issue_id: blocking_issue_id}, issue_id: blocked_issue_id)
        :ok
    end
  end

  @spec upsert_note(String.t(), map()) :: map()
  def upsert_note(issue_id, attrs) do
    attrs =
      attrs
      |> atomize_keys()
      |> Map.put(:gitlab_issue_id, issue_id)
      |> Map.put_new(:system, false)
      |> Map.put_new(:internal, false)
      |> Map.put_new(:resolvable, false)

    note =
      Repo.one(
        from(n in IssueNote,
          where: n.gitlab_issue_id == ^issue_id and n.note_id == ^attrs.note_id,
          limit: 1
        )
      )

    note =
      (note || %IssueNote{})
      |> IssueNote.changeset(attrs)
      |> Repo.insert_or_update!()

    append_event("gitlab_note_synced", "gitlab_sync", %{note_id: note.note_id}, issue_id: issue_id)
    plain(note)
  end

  @spec list_notes(String.t()) :: [map()]
  def list_notes(issue_id) do
    from(n in IssueNote,
      where: n.gitlab_issue_id == ^issue_id,
      order_by: [asc: coalesce(n.gitlab_created_at, n.inserted_at)]
    )
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @spec list_events(keyword()) :: [map()]
  def list_events(filters \\ []) do
    IssueEvent
    |> order_by([e], desc: e.inserted_at)
    |> limit(500)
    |> Repo.all()
    |> Enum.map(&plain/1)
    |> apply_event_filters(filters)
  end

  @spec record_event(String.t(), String.t(), map(), keyword()) :: map()
  def record_event(event_type, source, payload \\ %{}, opts \\ []) do
    append_event(event_type, source, payload, opts)
  end

  @spec put_cursor(String.t(), String.t(), map()) :: map()
  def put_cursor(source, cursor_name, attrs) do
    attrs =
      attrs
      |> atomize_keys()
      |> Map.put(:source, source)
      |> Map.put(:cursor_name, cursor_name)

    cursor =
      Repo.one(
        from(c in SyncCursor,
          where: c.source == ^source and c.cursor_name == ^cursor_name,
          limit: 1
        )
      )

    (cursor || %SyncCursor{})
    |> SyncCursor.changeset(attrs)
    |> Repo.insert_or_update!()
    |> plain()
  end

  @spec cursors() :: map()
  def cursors do
    SyncCursor
    |> Repo.all()
    |> Map.new(fn cursor -> {cursor_key(cursor.source, cursor.cursor_name), plain(cursor)} end)
  end

  @spec create_run(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_run(issue_id, attrs \\ %{}) do
    if Repo.get(Issue, issue_id) do
      run_number = next_run_number(issue_id)

      attrs =
        attrs
        |> atomize_keys()
        |> Map.put(:gitlab_issue_id, issue_id)
        |> Map.put(:run_number, run_number)
        |> Map.put_new(:status, "queued")
        |> Map.put_new(:mode, "workflow")
        |> Map.put_new(:needs_operator_input, false)

      run =
        %AgentRun{}
        |> AgentRun.changeset(attrs)
        |> Repo.insert!()

      append_event("agent_run_created", "agent", %{run_id: run.id, status: run.status}, issue_id: issue_id)
      {:ok, decorate_run(run)}
    else
      {:error, :issue_not_found}
    end
  end

  @spec update_run(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_run(run_id, attrs) do
    case Repo.get(AgentRun, run_id) do
      nil ->
        {:error, :run_not_found}

      run ->
        run =
          run
          |> AgentRun.changeset(atomize_keys(attrs))
          |> Repo.update!()

        {:ok, decorate_run(run)}
    end
  end

  @spec list_runs(keyword()) :: [map()]
  def list_runs(filters \\ []) do
    AgentRun
    |> order_by([r], desc: r.inserted_at)
    |> Repo.all()
    |> Enum.map(&decorate_run/1)
    |> apply_run_filters(filters)
  end

  @spec get_run(String.t()) :: map() | nil
  def get_run(run_id) do
    case Repo.get(AgentRun, run_id) do
      nil -> nil
      run -> decorate_run(run)
    end
  end

  @spec add_run_event(String.t(), String.t(), String.t() | nil, map()) :: {:ok, map()} | {:error, term()}
  def add_run_event(run_id, event_type, message \\ nil, payload \\ %{}) do
    if Repo.get(AgentRun, run_id) do
      event =
        %AgentRunEvent{}
        |> AgentRunEvent.changeset(%{
          agent_run_id: run_id,
          event_type: event_type,
          message: message,
          payload: payload || %{}
        })
        |> Repo.insert!()
        |> plain()

      {:ok, event}
    else
      {:error, :run_not_found}
    end
  end

  @spec list_run_events(String.t()) :: [map()]
  def list_run_events(run_id) do
    from(e in AgentRunEvent,
      where: e.agent_run_id == ^run_id,
      order_by: [asc: e.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @spec create_runtime_block(String.t(), String.t(), String.t() | nil, map(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def create_runtime_block(issue_id, block_type, message, payload \\ %{}, run_id \\ nil) do
    cond do
      block_type not in @block_types ->
        {:error, :invalid_block_type}

      is_nil(Repo.get(Issue, issue_id)) ->
        {:error, :issue_not_found}

      true ->
        block =
          %RuntimeBlock{}
          |> RuntimeBlock.changeset(%{
            gitlab_issue_id: issue_id,
            agent_run_id: run_id,
            block_type: block_type,
            message: message,
            payload: payload || %{}
          })
          |> Repo.insert!()

        append_event("runtime_block_created", "system", %{block_id: block.id, block_type: block_type}, issue_id: issue_id, run_id: run_id)
        {:ok, decorate_block(block)}
    end
  end

  @spec resolve_runtime_block(String.t()) :: {:ok, map()} | {:error, term()}
  def resolve_runtime_block(block_id) do
    case Repo.get(RuntimeBlock, block_id) do
      nil ->
        {:error, :block_not_found}

      block ->
        block =
          block
          |> RuntimeBlock.changeset(%{resolved_at: now()})
          |> Repo.update!()

        append_event("runtime_block_resolved", "local_ui", %{block_id: block.id}, issue_id: block.gitlab_issue_id, run_id: block.agent_run_id)
        {:ok, decorate_block(block)}
    end
  end

  @spec list_open_runtime_blocks() :: [map()]
  def list_open_runtime_blocks do
    from(b in RuntimeBlock,
      where: is_nil(b.resolved_at),
      order_by: [asc: b.inserted_at]
    )
    |> Repo.all()
    |> Enum.map(&decorate_block/1)
  end

  @spec snapshot() :: map()
  def snapshot do
    %{
      project: project(),
      issues: list_issues(),
      cursors: cursors(),
      runs: list_runs(),
      runtime_blocks: list_runtime_blocks(),
      open_runtime_blocks: list_open_runtime_blocks(),
      events: list_events(),
      started_at: started_at()
    }
  end

  defp current_project! do
    ProjectSetting
    |> order_by([p], asc: p.inserted_at)
    |> limit(1)
    |> Repo.one!()
  end

  defp ensure_workflow_state(issue_id, status \\ "triage", reason \\ nil) do
    case Repo.one(from(w in WorkflowState, where: w.gitlab_issue_id == ^issue_id, limit: 1)) do
      nil ->
        %WorkflowState{}
        |> WorkflowState.changeset(%{
          gitlab_issue_id: issue_id,
          status: status,
          priority: "none",
          last_transition_at: now(),
          last_transition_reason: reason
        })
        |> Repo.insert!()

      workflow ->
        workflow
    end
  end

  defp decorate_issue(%Issue{} = issue) do
    workflow = ensure_workflow_state(issue.id)
    plain_issue = plain(issue)

    plain_issue
    |> Map.put(:identifier, issue_identifier(issue))
    |> Map.put(:workflow_state, plain(workflow))
    |> Map.put(:workflow_status, workflow.status)
    |> Map.put(:priority, workflow.priority)
    |> Map.put(:blockers, blocker_dtos(issue.id))
    |> Map.put(:blocked_by_count, blocked_by_count(issue.id))
    |> Map.put(:active_run_id, active_run_id(issue.id))
    |> Map.put(:last_run_status, last_run_status(issue.id))
  end

  defp maybe_decorate_issue(nil), do: nil
  defp maybe_decorate_issue(issue), do: decorate_issue(issue)

  defp undecorate(issue) when is_map(issue) do
    Map.drop(issue, [:identifier, :workflow_state, :workflow_status, :priority, :blockers, :blocked_by_count, :active_run_id, :last_run_status])
  end

  defp tracker_issue(issue) when is_map(issue) do
    issue =
      case issue do
        %Issue{} -> decorate_issue(issue)
        %{workflow_status: _} -> issue
        %{id: id} -> get_issue(id)
      end

    %Tracker.Issue{
      id: issue.id,
      identifier: issue.identifier,
      iid: issue.iid,
      title: issue.title,
      description: issue.description,
      priority: priority_rank(issue.priority),
      state: issue.workflow_status,
      workflow_status: issue.workflow_status,
      gitlab_state: issue.gitlab_state,
      url: issue.web_url,
      web_url: issue.web_url,
      labels: issue.labels || [],
      assignees: issue.assignees || [],
      blockers: issue.blockers || [],
      blocked_by: blocker_refs(issue.id),
      notes_summary: notes_summary(issue.id),
      created_at: issue.gitlab_created_at,
      updated_at: issue.gitlab_updated_at
    }
  end

  defp issue_identifier(%Issue{} = issue) do
    case project_path() do
      nil -> "GL-#{issue.iid}"
      path -> "#{path}##{issue.iid}"
    end
  end

  defp project_path do
    case project() do
      %{path_with_namespace: path} when is_binary(path) and path != "" -> path
      _ -> nil
    end
  end

  defp blocker_dtos(issue_id) do
    from(e in IssueDependency,
      join: i in Issue,
      on: i.id == e.blocking_issue_id,
      join: w in WorkflowState,
      on: w.gitlab_issue_id == i.id,
      where: e.blocked_issue_id == ^issue_id,
      select: {e, i, w}
    )
    |> Repo.all()
    |> Enum.map(fn {edge, issue, workflow} ->
      %{
        issue_id: issue.id,
        iid: issue.iid,
        identifier: issue_identifier(issue),
        title: issue.title,
        status: workflow.status,
        reason: edge.reason
      }
    end)
  end

  defp blocker_refs(issue_id) do
    blocker_dtos(issue_id)
    |> Enum.map(&%{id: &1.issue_id, identifier: &1.identifier, state: &1.status})
  end

  defp blocked_by_count(issue_id) do
    Repo.one(from(e in IssueDependency, where: e.blocking_issue_id == ^issue_id, select: count(e.id)))
  end

  defp unresolved_dependency?(issue_id) do
    blocker_dtos(issue_id)
    |> Enum.any?(&(&1.status != "done"))
  end

  defp dependency_path?(from_issue_id, target_issue_id) do
    graph =
      IssueDependency
      |> Repo.all()
      |> Enum.group_by(& &1.blocked_issue_id, & &1.blocking_issue_id)

    do_dependency_path?(graph, from_issue_id, target_issue_id, MapSet.new())
  end

  defp do_dependency_path?(_graph, issue_id, issue_id, _seen), do: true

  defp do_dependency_path?(graph, issue_id, target_issue_id, seen) do
    if MapSet.member?(seen, issue_id) do
      false
    else
      graph
      |> Map.get(issue_id, [])
      |> Enum.any?(&do_dependency_path?(graph, &1, target_issue_id, MapSet.put(seen, issue_id)))
    end
  end

  defp active_run_id(issue_id) do
    Repo.one(
      from(r in AgentRun,
        where: r.gitlab_issue_id == ^issue_id and r.status in ["queued", "starting", "running", "blocked"],
        order_by: [desc: r.inserted_at],
        select: r.id,
        limit: 1
      )
    )
  end

  defp last_run_status(issue_id) do
    Repo.one(
      from(r in AgentRun,
        where: r.gitlab_issue_id == ^issue_id,
        order_by: [desc: r.inserted_at],
        select: r.status,
        limit: 1
      )
    )
  end

  defp next_run_number(issue_id) do
    (Repo.one(from(r in AgentRun, where: r.gitlab_issue_id == ^issue_id, select: max(r.run_number))) || 0) + 1
  end

  defp decorate_run(%AgentRun{} = run) do
    issue = Repo.get(Issue, run.gitlab_issue_id)

    run
    |> plain()
    |> Map.put(:issue, issue && decorate_issue(issue))
    |> Map.put(:issue_identifier, issue && issue_identifier(issue))
    |> Map.put(:issue_title, issue && issue.title)
    |> Map.put(:issue_web_url, issue && issue.web_url)
  end

  defp decorate_block(%RuntimeBlock{} = block) do
    issue = Repo.get(Issue, block.gitlab_issue_id)

    block
    |> plain()
    |> Map.put(:issue, issue && decorate_issue(issue))
    |> Map.put(:issue_identifier, issue && issue_identifier(issue))
    |> Map.put(:issue_title, issue && issue.title)
    |> Map.put(:issue_web_url, issue && issue.web_url)
  end

  defp list_runtime_blocks do
    RuntimeBlock
    |> order_by([b], desc: b.inserted_at)
    |> Repo.all()
    |> Enum.map(&decorate_block/1)
  end

  defp append_event(event_type, source, payload, opts) do
    source =
      if source in IssueEvent.sources() do
        source
      else
        "system"
      end

    %IssueEvent{}
    |> IssueEvent.changeset(%{
      gitlab_issue_id: Keyword.get(opts, :issue_id),
      event_type: event_type,
      source: source,
      actor: Keyword.get(opts, :actor),
      payload: payload || %{},
      run_id: Keyword.get(opts, :run_id)
    })
    |> Repo.insert!()
    |> plain()
  end

  defp apply_issue_filters(issues, filters) do
    Enum.filter(issues, fn issue ->
      Enum.all?(filters, fn
        {:status, status} -> issue.workflow_status == status
        {:gitlab_state, state} -> issue.gitlab_state == state
        {:search, search} -> issue_matches_search?(issue, search)
        _ -> true
      end)
    end)
  end

  defp apply_event_filters(events, filters) do
    Enum.filter(events, fn event ->
      Enum.all?(filters, fn
        {:issue_id, issue_id} -> event.gitlab_issue_id == issue_id
        {:run_id, run_id} -> event.run_id == run_id
        _ -> true
      end)
    end)
  end

  defp apply_run_filters(runs, filters) do
    Enum.filter(runs, fn run ->
      Enum.all?(filters, fn
        {:issue_id, issue_id} -> run.gitlab_issue_id == issue_id
        _ -> true
      end)
    end)
  end

  defp issue_matches_search?(_issue, search) when search in [nil, ""], do: true

  defp issue_matches_search?(issue, search) do
    haystack = Enum.join([issue.identifier, issue.title, issue.description_preview], " ") |> String.downcase()
    String.contains?(haystack, String.downcase(search))
  end

  defp labels_satisfy?(issue_labels, required_labels) do
    normalized = MapSet.new(issue_labels || [], &normalize_label/1)
    Enum.all?(required_labels || [], &MapSet.member?(normalized, normalize_label(&1)))
  end

  defp notes_summary(issue_id) do
    case list_notes(issue_id) do
      [] -> nil
      notes -> notes |> Enum.take(-3) |> Enum.map(& &1.body) |> Enum.join("\n\n")
    end
  end

  defp allowed_transition?(same, same), do: true
  defp allowed_transition?(from, _to) when from in ["done", "canceled"], do: false
  defp allowed_transition?(_from, "canceled"), do: true
  defp allowed_transition?("triage", "todo"), do: true
  defp allowed_transition?("todo", status), do: status in ["in_progress", "blocked"]
  defp allowed_transition?("in_progress", status), do: status in ["blocked", "review", "done", "todo"]
  defp allowed_transition?("blocked", status), do: status in ["todo", "canceled"]
  defp allowed_transition?("review", status), do: status in ["todo", "done"]
  defp allowed_transition?(_from, _to), do: false

  defp priority_rank("urgent"), do: 1
  defp priority_rank("high"), do: 2
  defp priority_rank("medium"), do: 3
  defp priority_rank("low"), do: 4
  defp priority_rank(_priority), do: nil

  defp normalize_label(label) when is_binary(label), do: label |> String.trim() |> String.downcase()
  defp normalize_label(label), do: label |> to_string() |> normalize_label()

  defp normalize_status(status) when is_binary(status), do: status |> String.trim() |> String.downcase()
  defp normalize_status(status), do: to_string(status)

  defp normalize_priority(priority) when is_binary(priority), do: priority |> String.trim() |> String.downcase()
  defp normalize_priority(priority), do: to_string(priority)

  defp cursor_key(source, cursor_name), do: "#{source}:#{cursor_name}"

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) -> {String.to_atom(key), value}
      pair -> pair
    end)
  end

  defp maybe_plain(nil), do: nil
  defp maybe_plain(schema), do: plain(schema)

  defp plain(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> Map.drop([:__meta__, :project_setting, :issue, :blocked_issue, :blocking_issue, :agent_run])
    |> Enum.reject(fn {_key, value} -> match?(%Ecto.Association.NotLoaded{}, value) end)
    |> Map.new()
  end

  defp plain(map) when is_map(map), do: map

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp started_at do
    Agent.get(__MODULE__, & &1.started_at)
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end
end
