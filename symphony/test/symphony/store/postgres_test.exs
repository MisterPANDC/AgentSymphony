defmodule SymphonyElixir.Store.PostgresTest do
  use ExUnit.Case, async: false

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
  alias SymphonyElixir.{Repo, Store}

  @moduletag :postgres

  setup do
    if Store.configured_backend() == :postgres do
      clean_database()
    end

    :ok
  end

  test "persists issues, workflow, runs, events, and runtime blocks in PostgreSQL" do
    Store.upsert_project(%{
      api_root: "https://gitlab.example.com/api/v4",
      project_ref: "group/project",
      project_id: 42,
      path_with_namespace: "group/project",
      name: "Project",
      web_url: "https://gitlab.example.com/group/project",
      visibility: "private"
    })

    issue =
      Store.upsert_issue(%{
        gitlab_issue_id: 91_000,
        gitlab_project_id: 42,
        iid: 100,
        web_url: "https://gitlab.example.com/group/project/-/issues/100",
        title: "Persist me",
        description: "Body",
        description_preview: "Body",
        gitlab_state: "opened",
        labels: ["backend"],
        assignees: [],
        raw_gitlab: %{"iid" => 100}
      })

    assert Repo.aggregate(Issue, :count) == 1
    assert Repo.one(from(w in WorkflowState, where: w.gitlab_issue_id == ^issue.id)).status == "triage"

    assert {:ok, workflow} = Store.transition_workflow(issue.id, "todo", reason: "ready")
    assert workflow.status == "todo"
    assert Repo.one(from(w in WorkflowState, where: w.gitlab_issue_id == ^issue.id)).status == "todo"

    assert {:ok, run} = Store.create_run(issue.id, %{status: "running", mode: "workflow"})
    assert {:ok, run_event} = Store.add_run_event(run.id, "heartbeat", "started", %{step: 1})
    assert run_event.agent_run_id == run.id

    assert {:ok, block} =
             Store.create_runtime_block(issue.id, "operator_input", "Need approval", %{field: "scope"}, run.id)

    assert [%{id: block_id, agent_run_id: run_id}] = Store.list_open_runtime_blocks()
    assert block_id == block.id
    assert run_id == run.id
    assert Repo.aggregate(AgentRun, :count) == 1
    assert Repo.aggregate(AgentRunEvent, :count) == 1
    assert Repo.aggregate(RuntimeBlock, :count) == 1
    assert Repo.aggregate(IssueEvent, :count) >= 4
  end

  defp clean_database do
    Repo.delete_all(RuntimeBlock)
    Repo.delete_all(AgentRunEvent)
    Repo.delete_all(AgentRun)
    Repo.delete_all(IssueEvent)
    Repo.delete_all(IssueDependency)
    Repo.delete_all(IssueNote)
    Repo.delete_all(WorkflowState)
    Repo.delete_all(Issue)
    Repo.delete_all(SyncCursor)
    Repo.delete_all(ProjectSetting)
  end
end
