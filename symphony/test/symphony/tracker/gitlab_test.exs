defmodule SymphonyElixir.Tracker.GitLabTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Store
  alias SymphonyElixir.GitLab.IssueLifecycle
  alias SymphonyElixir.Tracker.GitLab

  setup do
    previous_secret = System.get_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET")
    System.put_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", "tracker-test-secret")
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: followup_plug())

    project =
      Store.upsert_project(%{
        api_root: "https://gitlab.example.com/api/v4",
        project_ref: "123",
        project_id: 123,
        path_with_namespace: "group/project",
        name: "Project",
        web_url: "https://gitlab.example.com/group/project",
        visibility: "private"
      })

    assert {:ok, _project} = Store.put_project_access_token(project.id, "test-token")

    on_exit(fn ->
      restore_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", previous_secret)
      Application.delete_env(:symphony_elixir, :gitlab_req_options)
    end)

    {:ok, project: project}
  end

  test "creates a follow-up issue with related and blocked relationships", %{project: project} do
    current = seed_issue(10, project.id)

    assert {:ok, result} =
             GitLab.create_followup_issue(current.id, %{
               title: "Extract reusable importer",
               description: "Move importer code into a shared module.",
               acceptance_criteria: ["Shared importer exists", "Current behavior is unchanged"],
               labels: ["follow-up"],
               related_to_current_issue: true,
               blocked_by_current_issue: true
             })

    created = result.issue
    assert created.iid == 11
    assert created.workflow_status == "triage"
    assert result.relationship_flags.related_to_current_issue == true
    assert result.relationship_flags.blocked_by_current_issue == true
    assert result.note_created == true

    current = Store.get_issue(current.id)
    created = Store.get_issue(created.id)

    assert [%{issue_id: related_id}] = current.relations.related
    assert related_id == created.id
    assert [%{issue_id: blocked_id}] = current.relations.blocks
    assert blocked_id == created.id
    assert [%{issue_id: blocker_id}] = created.relations.blocked_by
    assert blocker_id == current.id
    assert created.is_blocked == true
  end

  test "agent transition to canceled closes the GitLab issue", %{project: project} do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: lifecycle_plug())
    current = seed_issue(20, project.id)

    assert {:ok, _todo} = Store.transition_workflow(current.id, "todo", reason: "accepted")
    assert :ok = GitLab.update_issue_state(current.id, "canceled")

    current = Store.get_issue(current.id)
    assert current.workflow_status == "canceled"
    assert current.gitlab_state == "closed"
  end

  test "agent restoration from canceled reopens the GitLab issue with a reopened label", %{project: project} do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: lifecycle_plug())
    current = seed_issue(21, project.id, "closed")

    assert {:ok, _todo} = Store.transition_workflow(current.id, "todo", reason: "accepted")
    assert {:ok, _canceled} = Store.transition_workflow(current.id, "canceled", reason: "no longer needed")
    assert :ok = GitLab.update_issue_state(current.id, "todo")

    current = Store.get_issue(current.id)
    assert current.workflow_status == "todo"
    assert current.gitlab_state == "opened"
    assert IssueLifecycle.reopened_label() in current.labels
  end

  defp seed_issue(iid, project_setting_id, gitlab_state \\ "opened") do
    Store.upsert_issue(%{
      gitlab_issue_id: 90_000 + iid,
      gitlab_project_id: 123,
      gitlab_project_setting_id: project_setting_id,
      iid: iid,
      web_url: "https://gitlab.example.com/group/project/-/issues/#{iid}",
      title: "Issue #{iid}",
      description: "Body #{iid}",
      description_preview: "Body #{iid}",
      gitlab_state: gitlab_state,
      labels: [],
      assignees: [],
      raw_gitlab: %{}
    })
  end

  defp followup_plug do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]

      case {conn.method, conn.request_path} do
        {"POST", "/api/v4/projects/123/issues"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)

          assert payload["title"] == "Extract reusable importer"
          assert payload["description"] =~ "## Acceptance Criteria"
          assert payload["description"] =~ "Created as a follow-up from"
          assert payload["labels"] == "follow-up"

          Req.Test.json(conn, %{
            "id" => 90_011,
            "project_id" => 123,
            "iid" => 11,
            "web_url" => "https://gitlab.example.com/group/project/-/issues/11",
            "title" => payload["title"],
            "description" => payload["description"],
            "state" => "opened",
            "labels" => ["follow-up"],
            "assignees" => []
          })

        {"POST", "/api/v4/projects/123/issues/10/notes"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload["body"] =~ "Created follow-up issue"
          assert payload["body"] =~ "blocked by the current issue"

          Req.Test.json(conn, %{
            "id" => 77,
            "body" => payload["body"],
            "system" => false,
            "internal" => false,
            "resolvable" => false,
            "author" => %{"id" => 1, "username" => "agent", "name" => "Agent"}
          })
      end
    end
  end

  defp lifecycle_plug do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]
      assert conn.method == "PUT"

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      case {conn.request_path, payload} do
        {"/api/v4/projects/123/issues/20", %{"state_event" => "close"}} ->
          Req.Test.json(conn, gitlab_issue(20, "closed", []))

        {"/api/v4/projects/123/issues/21", %{"state_event" => "reopen", "add_labels" => label}} ->
          assert label == IssueLifecycle.reopened_label()
          Req.Test.json(conn, gitlab_issue(21, "opened", [label]))
      end
    end
  end

  defp gitlab_issue(iid, state, labels) do
    %{
      "id" => 90_000 + iid,
      "project_id" => 123,
      "iid" => iid,
      "web_url" => "https://gitlab.example.com/group/project/-/issues/#{iid}",
      "title" => "Issue #{iid}",
      "description" => "Body #{iid}",
      "state" => state,
      "labels" => labels,
      "assignees" => []
    }
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
