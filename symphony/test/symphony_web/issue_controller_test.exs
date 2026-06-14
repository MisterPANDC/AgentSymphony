defmodule SymphonyElixirWeb.IssueControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias SymphonyElixir.Store
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

  test "creates an issue with the selected workflow status using user OAuth", %{identity: identity, iid: iid, project: project} do
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
        "description" => "Created from the board review column.",
        "labels" => "frontend, bug",
        "workflowStatus" => "review"
      })

    assert conn.status == 201

    payload = Jason.decode!(conn.resp_body)
    assert payload["issue"]["title"] == "Create from board"
    assert payload["issue"]["workflowStatus"] == "review"
    assert payload["issue"]["labels"] == ["frontend", "bug"]

    issue = Store.get_issue_by_iid(iid)
    assert issue.gitlab_project_setting_id == project.id
    assert issue.workflow_status == "review"

    transitions = Store.list_events(issue_id: issue.id) |> Enum.filter(&(&1.event_type == "workflow_transitioned"))
    assert transitions |> Enum.map(& &1.payload.to) |> Enum.reverse() == ["todo", "in_progress", "review"]
  end

  defp create_issue_plug(project_ref, project_id, iid, token) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer #{token}"]
      assert conn.method == "POST"
      assert conn.request_path == "/api/v4/projects/#{project_ref}/issues"

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)

      assert payload["title"] == "Create from board"
      assert payload["description"] == "Created from the board review column."
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

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
