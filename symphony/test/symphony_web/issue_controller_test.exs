defmodule SymphonyElixirWeb.IssueControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias SymphonyElixir.Store
  alias SymphonyElixir.GitLab.IssueLifecycle
  alias SymphonyElixirWeb.IssueController

  setup do
    previous_secret = System.get_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET")
    System.put_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", "issue-controller-test-secret")

    unique = System.unique_integer([:positive])
    project_id = 720_000 + unique
    iid = 820_000 + unique
    project_ref = to_string(project_id)
    token = "oauth-token-#{unique}"

    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: create_issue_plug(project_ref, project_id, iid, token))

    project =
      Store.upsert_project(%{
        api_root: "https://gitlab.example.com/api/v4",
        project_ref: project_ref,
        project_id: project_id,
        path_with_namespace: "group/project-#{unique}",
        name: "Project #{unique}",
        web_url: "https://gitlab.example.com/group/project-#{unique}",
        visibility: "private"
      })

    identity =
      Store.upsert_gitlab_identity(%{
        issuer: "https://gitlab.example.com",
        gitlab_user_id: to_string(unique),
        sub: "user-#{unique}",
        username: "dev-#{unique}"
      })

    Store.upsert_oauth_token(identity.id, %{"access_token" => token, "token_type" => "Bearer", "expires_in" => 3600})

    on_exit(fn ->
      restore_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", previous_secret)
      Application.delete_env(:symphony_elixir, :gitlab_req_options)
    end)

    {:ok, identity: identity, iid: iid, project: project}
  end

  test "creates an issue with a user-creatable workflow status using user OAuth", %{identity: identity, iid: iid, project: project} do
    conn =
      :post
      |> conn("/api/issues")
      |> Plug.Conn.assign(:current_user, %{
        identity_id: identity.id,
        gitlab_user_id: identity.gitlab_user_id,
        username: identity.username,
        project_setting_id: project.id,
        access_level: 30
      })

    conn =
      IssueController.create(conn, %{
        "title" => "Create from board",
        "description" => "Created from the board todo column.",
        "labels" => "frontend, bug",
        "workflowStatus" => "todo"
      })

    assert conn.status == 201

    payload = Jason.decode!(conn.resp_body)
    assert payload["issue"]["title"] == "Create from board"
    assert payload["issue"]["workflowStatus"] == "todo"
    assert payload["issue"]["labels"] == ["frontend", "bug"]

    issue = Store.get_issue_by_iid(iid)
    assert issue.gitlab_project_setting_id == project.id
    assert issue.workflow_status == "todo"

    transitions = Store.list_events(issue_id: issue.id) |> Enum.filter(&(&1.event_type == "workflow_transitioned"))
    assert transitions |> Enum.map(& &1.payload.to) |> Enum.reverse() == ["todo"]
    assert Enum.all?(transitions, &(&1.source == "user_ui"))
  end

  test "rejects non-initial statuses during issue creation", %{identity: identity, iid: iid, project: project} do
    for workflow_status <- ["review", "canceled"] do
      conn =
        :post
        |> conn("/api/issues")
        |> Plug.Conn.assign(:current_user, %{
          identity_id: identity.id,
          gitlab_user_id: identity.gitlab_user_id,
          username: identity.username,
          project_setting_id: project.id,
          access_level: 30
        })

      conn =
        IssueController.create(conn, %{
          "title" => "Create directly in #{workflow_status}",
          "workflowStatus" => workflow_status
        })

      assert conn.status == 400

      payload = Jason.decode!(conn.resp_body)
      assert payload["error"]["code"] == "invalid_workflow_status"
      assert Store.get_issue_by_iid(iid) == nil
    end
  end

  test "closes canceled issues and reopens restored canceled issues with a reopened label", %{identity: identity, iid: iid, project: project} do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: workflow_lifecycle_plug(project.project_ref, project.project_id, iid, identity))
    issue = seed_issue(iid, project)

    conn =
      :put
      |> conn("/api/issues/#{issue.id}/workflow")
      |> assign_user(identity, project)

    conn = IssueController.update_workflow(conn, %{"id" => issue.id, "status" => "canceled"})
    assert conn.status == 200

    payload = Jason.decode!(conn.resp_body)
    assert payload["issue"]["workflowStatus"] == "canceled"
    assert payload["issue"]["gitlabState"] == "closed"

    issue = Store.get_issue(issue.id)
    assert issue.workflow_status == "canceled"
    assert issue.gitlab_state == "closed"

    conn =
      :put
      |> conn("/api/issues/#{issue.id}/workflow")
      |> assign_user(identity, project)

    conn = IssueController.update_workflow(conn, %{"id" => issue.id, "status" => "todo"})
    assert conn.status == 200

    payload = Jason.decode!(conn.resp_body)
    assert payload["issue"]["workflowStatus"] == "todo"
    assert payload["issue"]["gitlabState"] == "opened"
    assert IssueLifecycle.reopened_label() in payload["issue"]["labels"]
  end

  defp create_issue_plug(project_ref, project_id, iid, token) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer #{token}"]
      assert conn.method == "POST"
      assert conn.request_path == "/api/v4/projects/#{project_ref}/issues"

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["title"] == "Create from board"
      assert payload["description"] == "Created from the board todo column."
      assert payload["labels"] == "frontend,bug"

      Req.Test.json(conn, %{
        "id" => 920_000 + iid,
        "project_id" => project_id,
        "iid" => iid,
        "web_url" => "https://gitlab.example.com/group/project/-/issues/#{iid}",
        "title" => payload["title"],
        "description" => payload["description"],
        "state" => "opened",
        "labels" => ["frontend", "bug"],
        "assignees" => []
      })
    end
  end

  defp workflow_lifecycle_plug(project_ref, project_id, iid, identity) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      assert conn.method == "PUT"
      assert conn.request_path == "/api/v4/projects/#{project_ref}/issues/#{iid}"

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      case payload do
        %{"state_event" => "close"} ->
          Req.Test.json(conn, gitlab_issue(project_id, iid, "closed", []))

        %{"state_event" => "reopen", "add_labels" => label} ->
          assert label == IssueLifecycle.reopened_label()
          Req.Test.json(conn, gitlab_issue(project_id, iid, "opened", [label]))
      end
    end
  end

  defp seed_issue(iid, project) do
    Store.upsert_issue(%{
      gitlab_issue_id: 920_000 + iid,
      gitlab_project_id: project.project_id,
      gitlab_project_setting_id: project.id,
      iid: iid,
      web_url: "https://gitlab.example.com/group/project/-/issues/#{iid}",
      title: "Lifecycle issue",
      description: "Body",
      description_preview: "Body",
      gitlab_state: "opened",
      labels: [],
      assignees: [],
      raw_gitlab: %{}
    })
  end

  defp gitlab_issue(project_id, iid, state, labels) do
    %{
      "id" => 920_000 + iid,
      "project_id" => project_id,
      "iid" => iid,
      "web_url" => "https://gitlab.example.com/group/project/-/issues/#{iid}",
      "title" => "Lifecycle issue",
      "description" => "Body",
      "state" => state,
      "labels" => labels,
      "assignees" => []
    }
  end

  defp assign_user(conn, identity, project) do
    Plug.Conn.assign(conn, :current_user, %{
      identity_id: identity.id,
      gitlab_user_id: identity.gitlab_user_id,
      username: identity.username,
      project_setting_id: project.id,
      access_level: 30
    })
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
