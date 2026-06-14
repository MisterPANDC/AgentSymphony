defmodule SymphonyElixir.Sync.PollerTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Store
  alias SymphonyElixir.GitLab.IssueLifecycle
  alias SymphonyElixir.Sync.Poller

  setup do
    previous_secret = System.get_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET")
    System.put_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", "poller-test-secret")
    Application.delete_env(:symphony_elixir, :gitlab_req_options)

    on_exit(fn ->
      restore_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", previous_secret)
      Application.delete_env(:symphony_elixir, :gitlab_req_options)
    end)

    :ok
  end

  test "reset_issue_cursor clears the incremental issue sync marker" do
    timestamp = ~U[2026-06-13 16:50:02.647149Z]

    Store.put_cursor("gitlab", "gitlab_issues_updated_after", %{
      cursor_value: DateTime.to_iso8601(timestamp),
      last_success_at: timestamp,
      last_attempt_at: timestamp,
      last_error: "old error",
      last_error_at: timestamp
    })

    assert :ok = Poller.reset_issue_cursor()

    cursor = Store.cursors()["gitlab:gitlab_issues_updated_after"]
    assert cursor.cursor_value == nil
    assert cursor.last_success_at == nil
    assert cursor.last_attempt_at == nil
    assert cursor.last_error == nil
    assert cursor.last_error_at == nil
  end

  test "reset_issue_cursor clears only the selected project marker" do
    timestamp = ~U[2026-06-13 16:50:02.647149Z]
    project = Store.upsert_project(project_attrs(30_101))
    other_project = Store.upsert_project(project_attrs(30_102))

    Store.put_cursor("gitlab", "gitlab_issues_updated_after:#{project.id}", %{
      cursor_value: DateTime.to_iso8601(timestamp),
      last_success_at: timestamp,
      last_attempt_at: timestamp,
      last_error: "old error",
      last_error_at: timestamp
    })

    Store.put_cursor("gitlab", "gitlab_issues_updated_after:#{other_project.id}", %{
      cursor_value: DateTime.to_iso8601(timestamp),
      last_success_at: timestamp,
      last_attempt_at: timestamp
    })

    assert :ok = Poller.reset_issue_cursor(project.id)

    cursors = Store.cursors()
    cursor = cursors["gitlab:gitlab_issues_updated_after:#{project.id}"]
    other_cursor = cursors["gitlab:gitlab_issues_updated_after:#{other_project.id}"]

    assert cursor.cursor_value == nil
    assert cursor.last_success_at == nil
    assert cursor.last_attempt_at == nil
    assert cursor.last_error == nil
    assert cursor.last_error_at == nil
    assert other_cursor.cursor_value == DateTime.to_iso8601(timestamp)
    assert other_cursor.last_success_at == timestamp
  end

  test "full sync writes issues with the current project setting id" do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: sync_plug())

    project =
      Store.upsert_project(%{
        api_root: "https://gitlab.example.com/api/v4",
        project_ref: "321",
        project_id: 321,
        path_with_namespace: "group/project",
        name: "Project",
        web_url: "https://gitlab.example.com/group/project",
        visibility: "private"
      })

    assert {:ok, _project} = Store.put_project_access_token(project.id, "test-token")
    assert :ok = Poller.reset_issue_cursor()
    assert {:ok, %{queued: true}} = Poller.refresh()

    issue =
      eventually(fn ->
        Store.get_issue_by_iid(77)
      end)

    assert issue.gitlab_project_setting_id == project.id
    assert Enum.any?(Store.list_issues(project_setting_id: project.id), &(&1.id == issue.id))
    assert Store.cursors()["gitlab:gitlab_issues_updated_after:#{project.id}"].last_success_at
  end

  test "external GitLab reopen restores canceled issues to triage and adds reopened label" do
    project_id = 84_000 + System.unique_integer([:positive])
    iid = 94_000 + System.unique_integer([:positive])
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: external_reopen_plug(project_id, iid))

    project = Store.upsert_project(project_attrs(project_id))
    assert {:ok, _project} = Store.put_project_access_token(project.id, "test-token")

    issue =
      Store.upsert_issue(%{
        gitlab_issue_id: 910_000 + iid,
        gitlab_project_id: project_id,
        gitlab_project_setting_id: project.id,
        iid: iid,
        web_url: "https://gitlab.example.com/group/project-#{project_id}/-/issues/#{iid}",
        title: "Canceled issue",
        description: "Body",
        description_preview: "Body",
        gitlab_state: "closed",
        labels: [],
        assignees: [],
        raw_gitlab: %{}
      })

    assert {:ok, _todo} = Store.transition_workflow(issue.id, "todo", source: "user_ui", reason: "accepted")
    assert {:ok, _canceled} = Store.transition_workflow(issue.id, "canceled", source: "user_ui", reason: "no longer needed")
    assert :ok = Poller.reset_issue_cursor(project.id)
    assert {:ok, %{queued: true}} = Poller.refresh()

    issue =
      eventually(fn ->
        case Store.get_issue(issue.id) do
          %{workflow_status: "triage", gitlab_state: "opened", labels: labels} = issue ->
            if IssueLifecycle.reopened_label() in labels, do: issue

          _issue ->
            nil
        end
      end)

    assert issue.workflow_status == "triage"
    assert issue.gitlab_state == "opened"
    assert IssueLifecycle.reopened_label() in issue.labels
  end

  test "explicit backfill attaches orphaned local issues to their project setting" do
    project_id = 80_000 + System.unique_integer([:positive])
    iid = 90_000 + System.unique_integer([:positive])
    project = Store.upsert_project(project_attrs(project_id))
    issue_id = inject_orphan_issue(project_id, iid)

    refute Enum.any?(Store.list_issues(project_setting_id: project.id), &(&1.id == issue_id))

    assert 1 = Store.backfill_issue_project_setting(project)

    assert issue = Store.get_issue(issue_id)
    assert issue.gitlab_project_setting_id == project.id
    assert Enum.any?(Store.list_issues(project_setting_id: project.id), &(&1.id == issue_id))
  end

  defp sync_plug do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]

      case {conn.method, conn.request_path} do
        {"GET", "/api/v4/projects/321"} ->
          Req.Test.json(conn, %{
            "id" => 321,
            "name" => "Project",
            "path_with_namespace" => "group/project",
            "web_url" => "https://gitlab.example.com/group/project",
            "visibility" => "private"
          })

        {"GET", "/api/v4/projects/321/issues"} ->
          conn = Plug.Conn.fetch_query_params(conn)
          refute Map.has_key?(conn.query_params, "updated_after")

          Req.Test.json(conn, [
            %{
              "id" => 90_077,
              "project_id" => 321,
              "iid" => 77,
              "web_url" => "https://gitlab.example.com/group/project/-/issues/77",
              "title" => "Poller issue",
              "description" => "Body",
              "state" => "opened",
              "labels" => [],
              "assignees" => [],
              "created_at" => "2026-06-12T19:00:10.517Z",
              "updated_at" => "2026-06-12T19:01:41.042Z"
            }
          ])
      end
    end
  end

  defp external_reopen_plug(project_id, iid) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]

      cond do
        conn.method == "GET" and conn.request_path == "/api/v4/projects/#{project_id}" ->
          Req.Test.json(conn, %{
            "id" => project_id,
            "name" => "Project #{project_id}",
            "path_with_namespace" => "group/project-#{project_id}",
            "web_url" => "https://gitlab.example.com/group/project-#{project_id}",
            "visibility" => "private"
          })

        conn.method == "GET" and conn.request_path == "/api/v4/projects/#{project_id}/issues" ->
          Req.Test.json(conn, [
            %{
              "id" => 910_000 + iid,
              "project_id" => project_id,
              "iid" => iid,
              "web_url" => "https://gitlab.example.com/group/project-#{project_id}/-/issues/#{iid}",
              "title" => "Canceled issue",
              "description" => "Body",
              "state" => "opened",
              "labels" => [],
              "assignees" => [],
              "created_at" => "2026-06-12T19:00:10.517Z",
              "updated_at" => "2026-06-12T19:01:41.042Z"
            }
          ])

        conn.method == "PUT" and conn.request_path == "/api/v4/projects/#{project_id}/issues/#{iid}" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload == %{"add_labels" => IssueLifecycle.reopened_label()}

          Req.Test.json(conn, %{
            "id" => 910_000 + iid,
            "project_id" => project_id,
            "iid" => iid,
            "web_url" => "https://gitlab.example.com/group/project-#{project_id}/-/issues/#{iid}",
            "title" => "Canceled issue",
            "description" => "Body",
            "state" => "opened",
            "labels" => [IssueLifecycle.reopened_label()],
            "assignees" => []
          })

        conn.method == "GET" and String.ends_with?(conn.request_path, "/issues") ->
          Req.Test.json(conn, [])

        conn.method == "GET" ->
          {fallback_project_id, fallback_project_ref} = project_ref_from_path(conn.request_path, project_id)

          Req.Test.json(conn, %{
            "id" => fallback_project_id,
            "name" => "Project #{fallback_project_ref}",
            "path_with_namespace" => "group/project-#{fallback_project_ref}",
            "web_url" => "https://gitlab.example.com/group/project-#{fallback_project_ref}",
            "visibility" => "private"
          })
      end
    end
  end

  defp project_ref_from_path(path, fallback_id) do
    ref =
      path
      |> String.replace_prefix("/api/v4/projects/", "")
      |> String.split("/", parts: 2)
      |> hd()

    id =
      case Integer.parse(ref) do
        {id, ""} -> id
        _ -> fallback_id
      end

    {id, ref}
  end

  defp project_attrs(project_id) do
    %{
      api_root: "https://gitlab.example.com/api/v4",
      project_ref: to_string(project_id),
      project_id: project_id,
      path_with_namespace: "group/project-#{project_id}",
      name: "Project #{project_id}",
      web_url: "https://gitlab.example.com/group/project-#{project_id}",
      visibility: "private"
    }
  end

  defp inject_orphan_issue(project_id, iid) do
    issue_id = "gitlab-#{project_id}-#{iid}"
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    :sys.replace_state(SymphonyElixir.Store.Json, fn state ->
      issue = %{
        id: issue_id,
        gitlab_issue_id: 900_000 + iid,
        gitlab_project_id: project_id,
        iid: iid,
        web_url: "https://gitlab.example.com/group/project-#{project_id}/-/issues/#{iid}",
        title: "Orphan issue",
        description: "Body",
        description_preview: "Body",
        gitlab_state: "opened",
        labels: [],
        assignees: [],
        confidential: false,
        inserted_at: now,
        updated_at: now,
        raw_gitlab: %{}
      }

      workflow_state = %{
        id: Ecto.UUID.generate(),
        gitlab_issue_id: issue_id,
        status: "triage",
        priority: "none",
        rank: nil,
        claimed_by: nil,
        claimed_at: nil,
        last_transition_at: now,
        last_transition_reason: "test orphan",
        inserted_at: now,
        updated_at: now
      }

      %{
        state
        | issues: Map.put(state.issues, issue_id, issue),
          issue_order: Enum.uniq(state.issue_order ++ [issue_id]),
          issue_by_iid: Map.put(state.issue_by_iid, to_string(iid), issue_id),
          issue_by_gitlab_id: Map.put(state.issue_by_gitlab_id, to_string(900_000 + iid), issue_id),
          workflow_states: Map.put(state.workflow_states, issue_id, workflow_state)
      }
    end)

    issue_id
  end

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    case fun.() do
      nil ->
        Process.sleep(25)
        eventually(fun, attempts - 1)

      value ->
        value
    end
  end

  defp eventually(fun, 0), do: fun.()

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
