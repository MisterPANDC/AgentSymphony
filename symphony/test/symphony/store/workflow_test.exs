defmodule SymphonyElixir.Store.WorkflowTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Store
  alias SymphonyElixirWeb.WorkflowTransition

  setup do
    Store.upsert_project(project_attrs())
    :ok
  end

  test "supports the GitLab workflow transition graph" do
    issue = seed_issue(10)

    assert issue.workflow_status == "triage"
    assert {:ok, todo} = Store.transition_workflow(issue.id, "todo", reason: "accepted")
    assert todo.status == "todo"

    assert {:ok, in_progress} = Store.transition_workflow(issue.id, "in_progress", claimed_by: "agent-1")
    assert in_progress.status == "in_progress"
    assert in_progress.claimed_by == "agent-1"
    assert {:error, :invalid_status} = Store.transition_workflow(issue.id, "blocked")

    assert {:ok, review} = Store.transition_workflow(issue.id, "review", reason: "ready for review")
    assert review.status == "review"

    assert {:ok, rework} = Store.transition_workflow(issue.id, "rework", reason: "changes requested")
    assert rework.status == "rework"

    assert {:ok, in_progress_again} = Store.transition_workflow(issue.id, "in_progress", reason: "addressing feedback")
    assert in_progress_again.status == "in_progress"

    assert {:ok, review_again} = Store.transition_workflow(issue.id, "review", reason: "ready again")
    assert review_again.status == "review"

    assert {:ok, merging} = Store.transition_workflow(issue.id, "merging", reason: "approved")
    assert merging.status == "merging"

    assert {:ok, done} = Store.transition_workflow(issue.id, "done", reason: "merged")
    assert done.status == "done"

    assert {:error, :invalid_transition} = Store.transition_workflow(issue.id, "triage")
  end

  test "allows work to return to triage for re-analysis" do
    todo_issue = seed_issue(11)
    {:ok, _todo} = Store.transition_workflow(todo_issue.id, "todo", reason: "accepted")
    assert {:ok, triage} = Store.transition_workflow(todo_issue.id, "triage", reason: "needs re-analysis")
    assert triage.status == "triage"

    in_progress_issue = seed_issue(12)
    {:ok, _todo} = Store.transition_workflow(in_progress_issue.id, "todo", reason: "accepted")
    {:ok, _in_progress} = Store.transition_workflow(in_progress_issue.id, "in_progress", reason: "started")
    assert {:ok, triage} = Store.transition_workflow(in_progress_issue.id, "triage", reason: "scope changed")
    assert triage.status == "triage"
  end

  test "restricts user initiated workflow transitions" do
    issue = seed_issue(13)

    assert {:ok, _todo} = Store.transition_workflow(issue.id, "todo", source: "user_ui", reason: "accepted")
    assert {:error, :invalid_transition} = Store.transition_workflow(issue.id, "in_progress", source: "user_ui")
    assert {:ok, _triage} = Store.transition_workflow(issue.id, "triage", source: "user_ui", reason: "needs triage")

    {:ok, _todo} = Store.transition_workflow(issue.id, "todo", reason: "accepted")
    {:ok, _in_progress} = Store.transition_workflow(issue.id, "in_progress", reason: "agent dispatch")
    assert {:error, :invalid_transition} = Store.transition_workflow(issue.id, "review", source: "user_ui")
    assert {:ok, _triage} = Store.transition_workflow(issue.id, "triage", source: "user_ui", reason: "scope changed")

    review_issue = seed_issue(14)
    {:ok, _todo} = Store.transition_workflow(review_issue.id, "todo", reason: "accepted")
    {:ok, _in_progress} = Store.transition_workflow(review_issue.id, "in_progress", reason: "agent dispatch")
    {:ok, _review} = Store.transition_workflow(review_issue.id, "review", reason: "ready")

    assert {:error, :invalid_transition} = Store.transition_workflow(review_issue.id, "done", source: "user_ui")
    assert {:ok, merging} = Store.transition_workflow(review_issue.id, "merging", source: "user_ui", reason: "approved")
    assert merging.status == "merging"
  end

  test "allows canceled issues to return to triage only" do
    issue = seed_issue(16)

    assert {:ok, _todo} = Store.transition_workflow(issue.id, "todo", source: "user_ui", reason: "accepted")
    assert {:ok, canceled} = Store.transition_workflow(issue.id, "canceled", source: "user_ui", reason: "no longer needed")
    assert canceled.status == "canceled"

    assert {:error, :invalid_transition} = Store.transition_workflow(issue.id, "todo", source: "user_ui")
    assert {:ok, triage} = Store.transition_workflow(issue.id, "triage", source: "user_ui", reason: "restore for re-analysis")
    assert triage.status == "triage"
  end

  test "requires confirmation and cancels active runs when leaving dispatch candidates" do
    issue = seed_issue(15)
    {:ok, _todo} = Store.transition_workflow(issue.id, "todo", reason: "accepted")
    {:ok, _in_progress} = Store.transition_workflow(issue.id, "in_progress", reason: "agent dispatch")
    {:ok, run} = Store.create_run(issue.id, %{status: "running", mode: "workflow"})

    active_issue = Store.get_issue(issue.id)

    assert {:error, :active_run_stop_confirmation_required} =
             WorkflowTransition.require_active_run_stop_confirmation(active_issue, "triage", %{})

    assert :ok = WorkflowTransition.require_active_run_stop_confirmation(active_issue, "triage", %{"confirmStopRun" => true})
    assert :ok = WorkflowTransition.maybe_stop_active_run(active_issue, "triage", "tester")

    canceled_run = Store.get_run(run.id)
    assert canceled_run.status == "canceled"
    assert canceled_run.exit_reason == "canceled by workflow status change to triage"
  end

  test "rejects self dependencies and dependency cycles" do
    blocked = seed_issue(20)
    blocking = seed_issue(21)

    assert {:error, :self_dependency} = Store.add_blocker(blocked.id, blocked.id)
    assert {:ok, edge} = Store.add_blocker(blocked.id, blocking.id, reason: "waiting on API")
    assert edge.blocked_issue_id == blocked.id
    assert edge.blocking_issue_id == blocking.id

    blockers = Store.list_blockers(blocked.id)
    assert [%{issue_id: blocking_issue_id, reason: "waiting on API"}] = blockers
    assert blocking_issue_id == blocking.id

    assert {:error, :dependency_cycle} = Store.add_blocker(blocking.id, blocked.id)
  end

  test "dependency blockers derive issue blocked state without changing workflow status" do
    blocked = seed_issue(30)
    blocking = seed_issue(31)

    {:ok, _todo} = Store.transition_workflow(blocked.id, "todo", reason: "accepted")
    {:ok, _blocking_todo} = Store.transition_workflow(blocking.id, "todo", reason: "accepted")

    assert blocked.id in candidate_ids()
    assert {:ok, _edge} = Store.add_blocker(blocked.id, blocking.id, reason: "waiting on API")

    blocked_issue = Store.get_issue(blocked.id)
    assert blocked_issue.workflow_status == "todo"
    assert blocked_issue.is_blocked == true
    assert blocked_issue.unresolved_blocker_count == 1
    refute blocked.id in candidate_ids()

    {:ok, _blocking_in_progress} = Store.transition_workflow(blocking.id, "in_progress", reason: "started")
    {:ok, _blocking_review} = Store.transition_workflow(blocking.id, "review", reason: "ready")
    {:ok, _blocking_merging} = Store.transition_workflow(blocking.id, "merging", reason: "approved")
    {:ok, _blocking_done} = Store.transition_workflow(blocking.id, "done", reason: "merged")

    unblocked_issue = Store.get_issue(blocked.id)
    assert unblocked_issue.workflow_status == "todo"
    assert unblocked_issue.is_blocked == false
    assert unblocked_issue.unresolved_blocker_count == 0
    assert blocked.id in candidate_ids()
  end

  test "issue relations expose related issues and blocks as separate concepts" do
    current = seed_issue(35)
    followup = seed_issue(36)

    {:ok, _current_todo} = Store.transition_workflow(current.id, "todo", reason: "accepted")
    {:ok, _followup_todo} = Store.transition_workflow(followup.id, "todo", reason: "accepted")

    assert {:ok, relation} =
             Store.add_issue_relation(current.id, followup.id, "relates_to",
               source: "agent",
               actor: "agent",
               reason: "agent-created follow-up"
             )

    assert relation.source_issue_id == current.id
    assert relation.target_issue_id == followup.id
    assert relation.relation_type == "relates_to"

    current_issue = Store.get_issue(current.id)
    followup_issue = Store.get_issue(followup.id)

    assert [%{issue_id: related_id}] = current_issue.relations.related
    assert related_id == followup.id
    assert [%{issue_id: reverse_related_id}] = followup_issue.relations.related
    assert reverse_related_id == current.id
    refute followup_issue.is_blocked
    assert followup.id in candidate_ids()

    assert {:ok, dependency} =
             Store.add_issue_relation(current.id, followup.id, "blocks",
               source: "agent",
               actor: "agent",
               reason: "follow-up depends on current issue"
             )

    assert dependency.blocking_issue_id == current.id
    assert dependency.blocked_issue_id == followup.id

    current_issue = Store.get_issue(current.id)
    followup_issue = Store.get_issue(followup.id)

    assert [%{issue_id: blocked_id}] = current_issue.relations.blocks
    assert blocked_id == followup.id
    assert [%{issue_id: blocker_id}] = followup_issue.relations.blocked_by
    assert blocker_id == current.id
    assert followup_issue.is_blocked
    refute followup.id in candidate_ids()
  end

  test "runtime blocks derive issue blocked state without changing workflow status" do
    issue = seed_issue(40)

    {:ok, _todo} = Store.transition_workflow(issue.id, "todo", reason: "accepted")
    {:ok, _in_progress} = Store.transition_workflow(issue.id, "in_progress", reason: "started")
    {:ok, run} = Store.create_run(issue.id, %{status: "running", mode: "workflow"})

    assert {:ok, block} = Store.create_runtime_block(issue.id, "operator_input", "Need approval", %{}, run.id)

    blocked_issue = Store.get_issue(issue.id)
    assert blocked_issue.workflow_status == "in_progress"
    assert blocked_issue.is_blocked == true
    assert blocked_issue.open_runtime_block_count == 1

    assert {:ok, _resolved} = Store.resolve_runtime_block(block.id)

    unblocked_issue = Store.get_issue(issue.id)
    assert unblocked_issue.workflow_status == "in_progress"
    assert unblocked_issue.is_blocked == false
    assert unblocked_issue.open_runtime_block_count == 0
  end

  test "project access token status stays attached to the matching project" do
    previous_secret = System.get_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET")
    System.put_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", "json-store-project-token-test")

    try do
      first = Store.upsert_project(project_attrs(42, "group/project-one", "Project One"))
      assert {:ok, first_with_token} = Store.put_project_access_token(first.id, "token-one")
      assert first_with_token.project_access_token_status == "configured"

      second = Store.upsert_project(project_attrs(43, "group/project-two", "Project Two"))
      assert second.project_access_token_status == "missing"

      statuses =
        Store.projects()
        |> Map.new(&{&1.project_id, &1.project_access_token_status})

      assert statuses[42] == "configured"
      assert statuses[43] == "missing"
    after
      restore_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", previous_secret)
    end
  end

  defp seed_issue(iid) do
    Store.upsert_issue(%{
      gitlab_issue_id: 90_000 + iid,
      gitlab_project_id: 42,
      iid: iid,
      web_url: "https://gitlab.example.com/group/project/-/issues/#{iid}",
      title: "Issue #{iid}",
      description: "Body #{iid}",
      description_preview: "Body #{iid}",
      gitlab_state: "opened",
      labels: [],
      assignees: [],
      raw_gitlab: %{}
    })
  end

  defp candidate_ids do
    Store.list_candidate_tracker_issues([], ["todo"])
    |> Enum.map(& &1.id)
  end

  defp project_attrs do
    project_attrs(42, "group/project", "Project")
  end

  defp project_attrs(project_id, path, name) do
    %{
      api_root: "https://gitlab.example.com/api/v4",
      project_ref: path,
      project_id: project_id,
      path_with_namespace: path,
      name: name,
      web_url: "https://gitlab.example.com/#{path}",
      visibility: "private"
    }
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
