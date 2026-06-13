defmodule SymphonyElixir.Tracker.GitLabTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Store
  alias SymphonyElixir.Tracker.GitLab

  setup do
    restore_env = put_gitlab_env()
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: followup_plug())

    Store.upsert_project(%{
      api_root: "https://gitlab.example.com/api/v4",
      project_ref: "123",
      project_id: 123,
      path_with_namespace: "group/project",
      name: "Project",
      web_url: "https://gitlab.example.com/group/project",
      visibility: "private"
    })

    on_exit(fn ->
      restore_env.()
      Application.delete_env(:symphony_elixir, :gitlab_req_options)
    end)

    :ok
  end

  test "creates a follow-up issue with related and blocked relationships" do
    current = seed_issue(10)

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

  defp seed_issue(iid) do
    Store.upsert_issue(%{
      gitlab_issue_id: 90_000 + iid,
      gitlab_project_id: 123,
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

  defp put_gitlab_env do
    keys = ["GITLAB_BASE_URL", "GITLAB_PROJECT_ID", "GITLAB_PROJECT_PATH", "GITLAB_PROJECT_API_URL", "GITLAB_TOKEN"]
    previous = Map.new(keys, &{&1, System.get_env(&1)})

    System.put_env("GITLAB_BASE_URL", "https://gitlab.example.com")
    System.put_env("GITLAB_PROJECT_ID", "123")
    System.delete_env("GITLAB_PROJECT_PATH")
    System.put_env("GITLAB_PROJECT_API_URL", "https://gitlab.example.com/api/v4/projects/123")
    System.put_env("GITLAB_TOKEN", "test-token")

    fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
