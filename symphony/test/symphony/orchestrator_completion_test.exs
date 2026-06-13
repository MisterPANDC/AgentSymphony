defmodule SymphonyElixir.OrchestratorCompletionTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Orchestrator
  alias SymphonyElixir.Orchestrator.State
  alias SymphonyElixir.Store
  alias SymphonyElixir.Tracker.Issue

  setup do
    Store.upsert_project(project_attrs())
    :ok
  end

  test "normal exit keeps active in_progress issue claimed for continuation retry" do
    issue = seed_issue(300)
    {:ok, _todo} = Store.transition_workflow(issue.id, "todo", reason: "accepted")
    {:ok, _in_progress} = Store.transition_workflow(issue.id, "in_progress", reason: "agent dispatch")
    {:ok, run} = Store.create_run(issue.id, %{status: "running", mode: "workflow", started_at: DateTime.utc_now()})

    state = claimed_state(issue.id)
    running_entry = running_entry(issue, run)

    state = Orchestrator.handle_agent_down_for_test(:normal, state, issue.id, running_entry, "session-1")

    assert Store.get_issue(issue.id).workflow_status == "in_progress"
    assert Store.get_run(run.id).status == "succeeded"
    assert MapSet.member?(state.claimed, issue.id)
    assert MapSet.member?(state.completed, issue.id)
    assert Map.has_key?(state.retry_attempts, issue.id)
  end

  test "normal exit releases review handoff status" do
    issue = seed_issue(303)
    {:ok, _todo} = Store.transition_workflow(issue.id, "todo", reason: "accepted")
    {:ok, _in_progress} = Store.transition_workflow(issue.id, "in_progress", reason: "agent dispatch")
    {:ok, _review} = Store.transition_workflow(issue.id, "review", reason: "agent ready for review")
    {:ok, run} = Store.create_run(issue.id, %{status: "running", mode: "workflow", started_at: DateTime.utc_now()})

    state = Orchestrator.handle_agent_down_for_test(:normal, claimed_state(issue.id), issue.id, running_entry(issue, run), "session-4")

    assert Store.get_issue(issue.id).workflow_status == "review"
    assert Store.get_run(run.id).status == "succeeded"
    refute MapSet.member?(state.claimed, issue.id)
    refute Map.has_key?(state.retry_attempts, issue.id)
  end

  test "normal exit preserves explicit done status" do
    issue = seed_issue(301)
    {:ok, _todo} = Store.transition_workflow(issue.id, "todo", reason: "accepted")
    {:ok, _in_progress} = Store.transition_workflow(issue.id, "in_progress", reason: "agent dispatch")
    {:ok, _review} = Store.transition_workflow(issue.id, "review", reason: "ready for review")
    {:ok, _merging} = Store.transition_workflow(issue.id, "merging", reason: "approved")
    {:ok, _done} = Store.transition_workflow(issue.id, "done", reason: "merged")
    {:ok, run} = Store.create_run(issue.id, %{status: "running", mode: "workflow", started_at: DateTime.utc_now()})

    state = Orchestrator.handle_agent_down_for_test(:normal, claimed_state(issue.id), issue.id, running_entry(issue, run), "session-2")

    assert Store.get_issue(issue.id).workflow_status == "done"
    assert Store.get_run(run.id).status == "succeeded"
    refute MapSet.member?(state.claimed, issue.id)
  end

  test "abnormal exit fails the run and keeps active status for retry" do
    issue = seed_issue(302)
    {:ok, _todo} = Store.transition_workflow(issue.id, "todo", reason: "accepted")
    {:ok, _in_progress} = Store.transition_workflow(issue.id, "in_progress", reason: "agent dispatch")
    {:ok, run} = Store.create_run(issue.id, %{status: "running", mode: "workflow", started_at: DateTime.utc_now()})

    state = Orchestrator.handle_agent_down_for_test(:crashed, claimed_state(issue.id), issue.id, running_entry(issue, run), "session-3")

    assert Store.get_issue(issue.id).workflow_status == "in_progress"
    assert Store.get_run(run.id).status == "failed"
    assert Map.has_key?(state.retry_attempts, issue.id)
    assert MapSet.member?(state.claimed, issue.id)
  end

  defp claimed_state(issue_id) do
    %State{
      claimed: MapSet.new([issue_id]),
      codex_totals: %{
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0,
        seconds_running: 0
      }
    }
  end

  defp running_entry(issue, run) do
    %{
      run_id: run.id,
      identifier: issue.identifier,
      issue: %Issue{
        id: issue.id,
        identifier: issue.identifier,
        iid: issue.iid,
        title: issue.title,
        state: issue.workflow_status,
        workflow_status: issue.workflow_status,
        gitlab_state: issue.gitlab_state,
        url: issue.web_url,
        web_url: issue.web_url
      },
      worker_host: nil,
      workspace_path: nil,
      retry_attempt: nil,
      started_at: DateTime.utc_now()
    }
  end

  defp seed_issue(iid) do
    Store.upsert_issue(%{
      gitlab_issue_id: 930_000 + iid,
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

  defp project_attrs do
    %{
      api_root: "https://gitlab.example.com/api/v4",
      project_ref: "group/project",
      project_id: 42,
      path_with_namespace: "group/project",
      name: "Project",
      web_url: "https://gitlab.example.com/group/project",
      visibility: "private"
    }
  end
end
