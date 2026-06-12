defmodule SymphonyElixir.Store.WorkflowTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Store

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

    assert {:error, :invalid_transition} = Store.transition_workflow(issue.id, "triage")
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
