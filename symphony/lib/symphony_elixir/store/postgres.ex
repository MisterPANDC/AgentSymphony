defmodule SymphonyElixir.Store.Postgres do
  @moduledoc """
  PostgreSQL-backed Store implementation for GitLab-backed Symphony.
  """

  use Agent

  import Ecto.Query

  alias SymphonyElixir.Auth.TokenVault
  alias SymphonyElixir.Persistence.AgentRun
  alias SymphonyElixir.Persistence.AgentRunEvent
  alias SymphonyElixir.Persistence.GitLabIdentity
  alias SymphonyElixir.Persistence.GitLabOAuthToken
  alias SymphonyElixir.Persistence.GitLabProjectMembership
  alias SymphonyElixir.Persistence.Issue
  alias SymphonyElixir.Persistence.IssueDependency
  alias SymphonyElixir.Persistence.IssueEvent
  alias SymphonyElixir.Persistence.IssueNote
  alias SymphonyElixir.Persistence.IssueRelation
  alias SymphonyElixir.Persistence.MergeRequest
  alias SymphonyElixir.Persistence.ProjectSetting
  alias SymphonyElixir.Persistence.RuntimeBlock
  alias SymphonyElixir.Persistence.SyncCursor
  alias SymphonyElixir.Persistence.WorkflowState
  alias SymphonyElixir.Repo
  alias SymphonyElixir.Tracker
  alias SymphonyElixir.Workflow.Transitions

  @workflow_statuses Transitions.statuses()
  @priorities WorkflowState.priorities()
  @block_types RuntimeBlock.block_types()
  @relation_types IssueRelation.relation_types()

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

    existing = find_project_setting(attrs)

    (existing || %ProjectSetting{})
    |> ProjectSetting.changeset(attrs)
    |> Repo.insert_or_update!()
    |> project_public()
  end

  @spec project() :: map() | nil
  def project do
    ProjectSetting
    |> order_by([p], asc: p.inserted_at)
    |> limit(1)
    |> Repo.one()
    |> maybe_project_public()
  end

  @spec projects() :: [map()]
  def projects do
    ProjectSetting
    |> order_by([p], desc: p.last_validated_at, asc: p.path_with_namespace)
    |> Repo.all()
    |> Enum.map(&project_public/1)
  end

  @spec project_by_id(String.t()) :: map() | nil
  def project_by_id(id) do
    case Repo.get(ProjectSetting, id) do
      nil -> nil
      project -> project_public(project)
    end
  end

  @spec upsert_gitlab_identity(map()) :: map()
  def upsert_gitlab_identity(attrs) do
    now = now()

    attrs =
      attrs
      |> atomize_keys()
      |> Map.update(:gitlab_user_id, nil, &to_string/1)
      |> Map.update(:sub, nil, &to_string/1)
      |> Map.put(:last_login_at, now)
      |> Map.put_new(:raw_claims, %{})

    identity =
      Repo.one(
        from(i in GitLabIdentity,
          where: i.issuer == ^attrs.issuer and i.gitlab_user_id == ^attrs.gitlab_user_id,
          limit: 1
        )
      )

    (identity || %GitLabIdentity{})
    |> GitLabIdentity.changeset(attrs)
    |> Repo.insert_or_update!()
    |> plain()
  end

  @spec upsert_oauth_token(String.t(), map()) :: map()
  def upsert_oauth_token(identity_id, attrs) do
    now = now()

    with {:ok, encrypted_access_token} <- TokenVault.seal(attrs["access_token"] || attrs[:access_token]),
         {:ok, encrypted_refresh_token} <- TokenVault.seal(attrs["refresh_token"] || attrs[:refresh_token]) do
      attrs = %{
        identity_id: identity_id,
        encrypted_access_token: encrypted_access_token,
        encrypted_refresh_token: encrypted_refresh_token || existing_refresh_token(identity_id),
        scopes: scopes(attrs),
        token_type: attrs["token_type"] || attrs[:token_type],
        expires_at: expires_at(attrs, now),
        last_refreshed_at: now
      }

      token =
        Repo.one(from(t in GitLabOAuthToken, where: t.identity_id == ^identity_id, limit: 1))

      (token || %GitLabOAuthToken{})
      |> GitLabOAuthToken.changeset(attrs)
      |> Repo.insert_or_update!()
      |> plain()
    else
      {:error, reason} -> raise "failed to seal OAuth token: #{inspect(reason)}"
    end
  end

  @spec oauth_token(String.t()) :: map() | nil
  def oauth_token(identity_id) do
    GitLabOAuthToken
    |> where([t], t.identity_id == ^identity_id)
    |> limit(1)
    |> Repo.one()
    |> maybe_plain()
  end

  @spec upsert_project_membership(String.t(), String.t(), map()) :: map()
  def upsert_project_membership(identity_id, project_setting_id, attrs) do
    raw_access_level = attrs[:access_level] || attrs["access_level"]
    access_level = normalize_access_level(raw_access_level)

    attrs =
      attrs
      |> atomize_keys()
      |> Map.update(:gitlab_user_id, nil, &to_string/1)
      |> Map.put(:access_level, access_level || raw_access_level)
      |> Map.put(:identity_id, identity_id)
      |> Map.put(:gitlab_project_setting_id, project_setting_id)
      |> Map.put(:last_checked_at, now())
      |> Map.put_new(:raw_gitlab, %{})

    membership =
      Repo.one(
        from(m in GitLabProjectMembership,
          where: m.identity_id == ^identity_id and m.gitlab_project_setting_id == ^project_setting_id,
          limit: 1
        )
      )

    (membership || %GitLabProjectMembership{})
    |> GitLabProjectMembership.changeset(attrs)
    |> Repo.insert_or_update!()
    |> plain()
  end

  defp normalize_access_level(level) when is_integer(level), do: level

  defp normalize_access_level(level) when is_binary(level) do
    case Integer.parse(level) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp normalize_access_level(_level), do: nil

  @spec put_project_access_token(String.t(), String.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def put_project_access_token(project_setting_id, token, identity_id \\ nil) do
    with %ProjectSetting{} = project <- Repo.get(ProjectSetting, project_setting_id) || {:error, :project_not_found},
         {:ok, encrypted_token} <- TokenVault.seal(token) do
      project =
        project
        |> ProjectSetting.changeset(%{
          encrypted_project_access_token: encrypted_token,
          project_access_token_set_by_identity_id: identity_id,
          project_access_token_set_at: now(),
          read_only: false
        })
        |> Repo.update!()

      {:ok, project_public(project)}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec project_access_token(map() | String.t()) :: {:ok, String.t()} | {:error, term()}
  def project_access_token(project_id) when is_binary(project_id) do
    case Repo.get(ProjectSetting, project_id) do
      nil -> {:error, :project_not_found}
      project -> project_access_token(project)
    end
  end

  def project_access_token(%ProjectSetting{} = project), do: open_project_access_token(project.encrypted_project_access_token)
  def project_access_token(%{encrypted_project_access_token: encrypted}), do: open_project_access_token(encrypted)
  def project_access_token(_project), do: {:error, :project_access_token_missing}

  @spec upsert_issue(map()) :: map()
  def upsert_issue(attrs) do
    attrs = atomize_keys(attrs)
    project = project_for_issue_attrs!(attrs)

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

  @spec backfill_issue_project_setting(map()) :: non_neg_integer()
  def backfill_issue_project_setting(project) when is_map(project) do
    project = atomize_keys(project)
    project_setting_id = project[:id]
    gitlab_project_id = parse_int(project[:project_id])

    if is_binary(project_setting_id) and is_integer(gitlab_project_id) do
      {count, _result} =
        Issue
        |> where([i], is_nil(i.gitlab_project_setting_id))
        |> where([i], i.gitlab_project_id == ^gitlab_project_id)
        |> Repo.update_all(set: [gitlab_project_setting_id: project_setting_id, updated_at: now()])

      count
    else
      0
    end
  end

  def backfill_issue_project_setting(_project), do: 0

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

  @spec list_candidate_tracker_issues([String.t()], [String.t()]) :: [Tracker.Issue.t()]
  def list_candidate_tracker_issues(required_labels, active_states) do
    active_statuses = MapSet.new(active_states || [], &normalize_status/1)

    list_issues(gitlab_state: "opened")
    |> Enum.filter(&MapSet.member?(active_statuses, &1.workflow_status))
    |> Enum.reject(&unresolved_dependency?(&1.id))
    |> Enum.reject(&(open_runtime_block_count(&1.id) > 0))
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
           true <- Transitions.allowed?(workflow.status, next_status, opts) || {:error, :invalid_transition} do
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
          Keyword.get(opts, :source, "user_ui"),
          %{
            from: previous_status,
            to: next_status,
            reason: Keyword.get(opts, :reason)
          },
          issue_id: issue_id,
          actor: Keyword.get(opts, :actor, "system")
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

        append_event("workflow_priority_changed", "user_ui", %{priority: priority}, issue_id: issue_id)
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
          created_by: Keyword.get(opts, :actor, "system"),
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

        append_event("dependency_added", Keyword.get(opts, :source, "user_ui"), Map.take(edge, [:blocking_issue_id, :reason]),
          issue_id: blocked_issue_id,
          actor: Keyword.get(opts, :actor, "system")
        )

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
        append_event("dependency_removed", "user_ui", %{blocking_issue_id: blocking_issue_id}, issue_id: blocked_issue_id)
        :ok
    end
  end

  @spec list_issue_relations(String.t()) :: map()
  def list_issue_relations(issue_id) do
    %{
      related: related_issue_dtos(issue_id),
      blocks: blocked_issue_dtos(issue_id),
      blocked_by: blocker_dtos(issue_id)
    }
  end

  @spec add_issue_relation(String.t(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add_issue_relation(source_issue_id, target_issue_id, relation_type, opts \\ []) do
    relation_type = normalize_relation_type(relation_type)

    cond do
      relation_type not in @relation_types ->
        {:error, :invalid_relation_type}

      source_issue_id == target_issue_id ->
        {:error, :self_relation}

      is_nil(Repo.get(Issue, source_issue_id)) or is_nil(Repo.get(Issue, target_issue_id)) ->
        {:error, :issue_not_found}

      true ->
        attrs = %{
          source_issue_id: source_issue_id,
          target_issue_id: target_issue_id,
          relation_type: relation_type,
          created_by: Keyword.get(opts, :actor, "system"),
          reason: Keyword.get(opts, :reason),
          metadata: Keyword.get(opts, :metadata, %{}) || %{}
        }

        relation =
          %IssueRelation{}
          |> IssueRelation.changeset(attrs)
          |> Repo.insert!(
            on_conflict: {:replace, [:reason, :created_by, :metadata, :updated_at]},
            conflict_target: [:source_issue_id, :target_issue_id, :relation_type]
          )
          |> plain()

        append_event(
          "issue_relation_added",
          Keyword.get(opts, :source, "user_ui"),
          Map.take(relation, [:target_issue_id, :relation_type, :reason, :metadata]),
          issue_id: source_issue_id,
          actor: Keyword.get(opts, :actor, "system")
        )

        {:ok, relation}
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

  @spec delete_note(String.t(), integer() | String.t()) :: :ok | {:error, term()}
  def delete_note(issue_id, note_id) do
    parsed_note_id = parse_int(note_id)

    case parsed_note_id do
      nil ->
        {:error, :invalid_note_id}

      note_id ->
        from(n in IssueNote,
          where: n.gitlab_issue_id == ^issue_id and n.note_id == ^note_id
        )
        |> Repo.delete_all()

        append_event("gitlab_note_deleted", "gitlab_sync", %{note_id: note_id}, issue_id: issue_id)
        :ok
    end
  end

  @spec replace_project_merge_requests(String.t(), [map()]) :: [map()]
  def replace_project_merge_requests(project_setting_id, entries) when is_binary(project_setting_id) and is_list(entries) do
    Repo.transaction(fn ->
      from(mr in MergeRequest, where: mr.gitlab_project_setting_id == ^project_setting_id)
      |> Repo.delete_all()

      entries
      |> Enum.map(fn entry ->
        issue_id = entry[:issue_id] || entry["issue_id"]

        attrs =
          entry
          |> Map.get(:attrs, Map.get(entry, "attrs", %{}))
          |> atomize_keys()
          |> Map.put(:gitlab_project_setting_id, project_setting_id)
          |> Map.put(:gitlab_issue_id, issue_id)
          |> Map.update(:labels, [], &(&1 || []))
          |> Map.update(:assignees, [], &(&1 || []))
          |> Map.update(:reviewers, [], &(&1 || []))
          |> Map.put_new(:draft, false)
          |> Map.put_new(:work_in_progress, false)

        %MergeRequest{}
        |> MergeRequest.changeset(attrs)
        |> Repo.insert!()
        |> plain()
      end)
    end)
    |> case do
      {:ok, merge_requests} -> merge_requests
      {:error, reason} -> raise inspect(reason)
    end
  end

  @spec upsert_merge_request(String.t(), String.t(), map()) :: map()
  def upsert_merge_request(project_setting_id, issue_id, attrs) when is_binary(project_setting_id) and is_binary(issue_id) do
    attrs =
      attrs
      |> atomize_keys()
      |> Map.put(:gitlab_project_setting_id, project_setting_id)
      |> Map.put(:gitlab_issue_id, issue_id)
      |> Map.update(:labels, [], &(&1 || []))
      |> Map.update(:assignees, [], &(&1 || []))
      |> Map.update(:reviewers, [], &(&1 || []))
      |> Map.put_new(:draft, false)
      |> Map.put_new(:work_in_progress, false)

    merge_request =
      Repo.one(
        from(mr in MergeRequest,
          where: mr.gitlab_issue_id == ^issue_id and mr.merge_request_id == ^attrs.merge_request_id,
          limit: 1
        )
      )

    (merge_request || %MergeRequest{})
    |> MergeRequest.changeset(attrs)
    |> Repo.insert_or_update!()
    |> plain()
  end

  @spec list_merge_requests(String.t()) :: [map()]
  def list_merge_requests(issue_id) do
    from(mr in MergeRequest,
      where: mr.gitlab_issue_id == ^issue_id,
      order_by: [desc: coalesce(mr.gitlab_updated_at, mr.updated_at), desc: mr.iid]
    )
    |> Repo.all()
    |> Enum.map(&plain/1)
  end

  @spec merge_request_counts([String.t()]) :: map()
  def merge_request_counts(issue_ids) when is_list(issue_ids) do
    wanted = Enum.filter(issue_ids, &is_binary/1)

    if wanted == [] do
      %{}
    else
      from(mr in MergeRequest,
        where: mr.gitlab_issue_id in ^wanted,
        group_by: mr.gitlab_issue_id,
        select: {mr.gitlab_issue_id, count(mr.id)}
      )
      |> Repo.all()
      |> Map.new(fn {issue_id, count} -> {issue_id, count} end)
    end
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

        append_event("runtime_block_resolved", "user_ui", %{block_id: block.id}, issue_id: block.gitlab_issue_id, run_id: block.agent_run_id)
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

  defp project_for_issue_attrs!(attrs) do
    gitlab_project_id = attrs[:gitlab_project_id] || attrs[:project_id]

    cond do
      is_integer(gitlab_project_id) ->
        Repo.one(from(p in ProjectSetting, where: p.project_id == ^gitlab_project_id, limit: 1)) || current_project!()

      is_binary(gitlab_project_id) ->
        case Integer.parse(gitlab_project_id) do
          {id, ""} -> Repo.one(from(p in ProjectSetting, where: p.project_id == ^id, limit: 1)) || current_project!()
          _ -> current_project!()
        end

      true ->
        current_project!()
    end
  end

  defp find_project_setting(%{api_root: api_root, project_id: project_id})
       when is_binary(api_root) and not is_nil(project_id) do
    Repo.one(from(p in ProjectSetting, where: p.api_root == ^api_root and p.project_id == ^project_id, limit: 1))
  end

  defp find_project_setting(%{api_root: api_root, project_ref: project_ref})
       when is_binary(api_root) and is_binary(project_ref) do
    Repo.one(from(p in ProjectSetting, where: p.api_root == ^api_root and p.project_ref == ^project_ref, limit: 1))
  end

  defp find_project_setting(_attrs), do: Repo.one(from(p in ProjectSetting, order_by: [asc: p.inserted_at], limit: 1))

  defp project_public(%ProjectSetting{} = project) do
    project
    |> plain()
    |> Map.drop([:encrypted_project_access_token, :project_access_token_set_by_identity_id])
    |> Map.put(:project_access_token_status, token_status(project.encrypted_project_access_token))
  end

  defp maybe_project_public(nil), do: nil
  defp maybe_project_public(project), do: project_public(project)

  defp open_project_access_token(nil), do: {:error, :project_access_token_missing}

  defp open_project_access_token(encrypted) do
    case TokenVault.open(encrypted) do
      {:ok, token} when is_binary(token) and token != "" -> {:ok, token}
      {:ok, _} -> {:error, :project_access_token_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  defp token_status(value) when is_binary(value) and value != "", do: "configured"
  defp token_status(_value), do: "missing"

  defp existing_refresh_token(identity_id) do
    case Repo.one(from(t in GitLabOAuthToken, where: t.identity_id == ^identity_id, limit: 1)) do
      nil -> nil
      token -> token.encrypted_refresh_token
    end
  end

  defp scopes(attrs) do
    scope = attrs["scope"] || attrs[:scope] || attrs["scopes"] || attrs[:scopes] || []

    cond do
      is_binary(scope) -> String.split(scope, ~r/[\s,]+/, trim: true)
      is_list(scope) -> Enum.map(scope, &to_string/1)
      true -> []
    end
  end

  defp expires_at(attrs, now) do
    expires_in = attrs["expires_in"] || attrs[:expires_in]

    case expires_in do
      seconds when is_integer(seconds) and seconds > 0 ->
        DateTime.add(now, seconds, :second)

      seconds when is_binary(seconds) ->
        case Integer.parse(seconds) do
          {int, ""} when int > 0 -> DateTime.add(now, int, :second)
          _ -> nil
        end

      _ ->
        nil
    end
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
    unresolved_blocker_count = unresolved_blocker_count(issue.id)
    open_runtime_block_count = open_runtime_block_count(issue.id)

    plain_issue
    |> Map.put(:identifier, issue_identifier(issue))
    |> Map.put(:workflow_state, plain(workflow))
    |> Map.put(:workflow_status, workflow.status)
    |> Map.put(:priority, workflow.priority)
    |> Map.put(:blockers, blocker_dtos(issue.id))
    |> Map.put(:relations, list_issue_relations(issue.id))
    |> Map.put(:is_blocked, unresolved_blocker_count > 0 or open_runtime_block_count > 0 or blocked_run?(issue.id))
    |> Map.put(:unresolved_blocker_count, unresolved_blocker_count)
    |> Map.put(:open_runtime_block_count, open_runtime_block_count)
    |> Map.put(:blocked_by_count, blocked_by_count(issue.id))
    |> Map.put(:active_run_id, active_run_id(issue.id))
    |> Map.put(:last_run_status, last_run_status(issue.id))
  end

  defp maybe_decorate_issue(nil), do: nil
  defp maybe_decorate_issue(issue), do: decorate_issue(issue)

  defp undecorate(issue) when is_map(issue) do
    Map.drop(issue, [
      :identifier,
      :workflow_state,
      :workflow_status,
      :priority,
      :blockers,
      :relations,
      :is_blocked,
      :unresolved_blocker_count,
      :open_runtime_block_count,
      :blocked_by_count,
      :active_run_id,
      :last_run_status
    ])
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
      is_blocked: issue.is_blocked || false,
      unresolved_blocker_count: issue.unresolved_blocker_count || 0,
      open_runtime_block_count: issue.open_runtime_block_count || 0,
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

  defp blocked_issue_dtos(issue_id) do
    from(e in IssueDependency,
      join: i in Issue,
      on: i.id == e.blocked_issue_id,
      join: w in WorkflowState,
      on: w.gitlab_issue_id == i.id,
      where: e.blocking_issue_id == ^issue_id,
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

  defp related_issue_dtos(issue_id) do
    IssueRelation
    |> where([r], r.relation_type == "relates_to" and (r.source_issue_id == ^issue_id or r.target_issue_id == ^issue_id))
    |> order_by([r], asc: r.inserted_at)
    |> Repo.all()
    |> Enum.map(fn relation ->
      related_issue_id =
        if relation.source_issue_id == issue_id do
          relation.target_issue_id
        else
          relation.source_issue_id
        end

      case Repo.get(Issue, related_issue_id) do
        nil ->
          nil

        issue ->
          workflow = ensure_workflow_state(issue.id)

          %{
            issue_id: issue.id,
            iid: issue.iid,
            identifier: issue_identifier(issue),
            title: issue.title,
            status: workflow.status,
            reason: relation.reason,
            relation_type: relation.relation_type,
            direction: if(relation.source_issue_id == issue_id, do: "outgoing", else: "incoming")
          }
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp blocker_refs(issue_id) do
    blocker_dtos(issue_id)
    |> Enum.map(&%{id: &1.issue_id, identifier: &1.identifier, state: &1.status})
  end

  defp blocked_by_count(issue_id) do
    Repo.one(from(e in IssueDependency, where: e.blocking_issue_id == ^issue_id, select: count(e.id)))
  end

  defp unresolved_blocker_count(issue_id) do
    blocker_dtos(issue_id)
    |> Enum.count(&(&1.status != "done"))
  end

  defp open_runtime_block_count(issue_id) do
    Repo.one(
      from(b in RuntimeBlock,
        where: b.gitlab_issue_id == ^issue_id and is_nil(b.resolved_at),
        select: count(b.id)
      )
    )
  end

  defp blocked_run?(issue_id) do
    Repo.exists?(
      from(r in AgentRun,
        where: r.gitlab_issue_id == ^issue_id and r.status == "blocked"
      )
    )
  end

  defp unresolved_dependency?(issue_id) do
    unresolved_blocker_count(issue_id) > 0
  end

  defp dependency_path?(from_issue_id, target_issue_id) do
    graph =
      IssueDependency
      |> Repo.all()
      |> Enum.group_by(& &1.blocked_issue_id, & &1.blocking_issue_id)

    do_dependency_path?(graph, from_issue_id, target_issue_id, MapSet.new())
  end

  defp normalize_relation_type(type) when is_binary(type), do: type |> String.trim() |> String.downcase()
  defp normalize_relation_type(type), do: to_string(type) |> normalize_relation_type()

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
        {:status, "blocked"} -> issue.is_blocked == true
        {:status, status} -> issue.workflow_status == status
        {:gitlab_state, state} -> issue.gitlab_state == state
        {:project_setting_id, project_setting_id} -> issue.gitlab_project_setting_id == project_setting_id
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
        {:project_setting_id, project_setting_id} -> get_in(run, [:issue, :gitlab_project_setting_id]) == project_setting_id
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
