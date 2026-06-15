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

  test "creates an issue note with attachments through user OAuth", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: note_attachment_plug(project.project_ref, iid, identity))
    upload = plug_upload("proof.txt", "attachment body", "text/plain")

    conn =
      :post
      |> conn("/api/issues/#{issue.id}/notes")
      |> assign_user(identity, project)

    conn = IssueController.create_note(conn, %{"id" => issue.id, "body" => "See attachment", "files" => upload})
    assert conn.status == 200

    [note] = Store.list_notes(issue.id)
    assert note.body =~ "See attachment"
    assert note.body =~ "/api/issues/#{issue.id}/uploads/0123456789abcdef0123456789abcdef/proof.txt"
  end

  test "creates an issue note with only attachments", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: note_attachment_plug(project.project_ref, iid, identity))
    upload = plug_upload("proof.txt", "attachment body", "text/plain")

    conn =
      :post
      |> conn("/api/issues/#{issue.id}/notes")
      |> assign_user(identity, project)

    conn = IssueController.create_note(conn, %{"id" => issue.id, "files[]" => [upload]})
    assert conn.status == 200

    [note] = Store.list_notes(issue.id)
    assert note.body == "![proof](/api/issues/#{issue.id}/uploads/0123456789abcdef0123456789abcdef/proof.txt)"
  end

  test "lists synced merge requests that close the issue", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)

    Store.replace_project_merge_requests(project.id, [
      %{issue_id: issue.id, attrs: merge_request_attrs(7, "Implement drawer", "Implements the UI.\n\nCloses ##{iid}")}
    ])

    conn =
      :get
      |> conn("/api/issues/#{issue.id}/merge_requests")
      |> assign_user(identity, project)

    conn = IssueController.merge_requests(conn, %{"id" => issue.id})
    assert conn.status == 200

    payload = Jason.decode!(conn.resp_body)
    assert [%{"iid" => 7, "title" => "Implement drawer"}] = payload["mergeRequests"]
  end

  test "updates merge request title description and labels through user OAuth", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    merge_request_iid = 7

    Store.replace_project_merge_requests(project.id, [
      %{issue_id: issue.id, attrs: merge_request_attrs(merge_request_iid, "Implement drawer", "Closes ##{iid}")}
    ])

    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: merge_request_update_plug(project.project_ref, merge_request_iid, identity))

    conn =
      :patch
      |> conn("/api/issues/#{issue.id}/merge_requests/#{merge_request_iid}/gitlab")
      |> assign_user(identity, project)

    conn =
      IssueController.update_merge_request_gitlab(conn, %{
        "id" => issue.id,
        "merge_request_iid" => to_string(merge_request_iid),
        "title" => "Updated MR",
        "description" => "Updated description",
        "labels" => "frontend,review"
      })

    assert conn.status == 200

    payload = Jason.decode!(conn.resp_body)
    assert payload["mergeRequest"]["title"] == "Updated MR"
    assert payload["mergeRequest"]["description"] == "Updated description"
    assert payload["mergeRequest"]["labels"] == ["frontend", "review"]

    assert [%{title: "Updated MR", description: "Updated description", labels: ["frontend", "review"]}] = Store.list_merge_requests(issue.id)
  end

  test "lists and manages merge request notes through user OAuth", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    merge_request_iid = 7

    Store.replace_project_merge_requests(project.id, [
      %{issue_id: issue.id, attrs: merge_request_attrs(merge_request_iid, "Implement drawer", "Closes ##{iid}")}
    ])

    {:ok, notes} = Agent.start_link(fn -> [raw_gitlab_note(54, "Existing MR note")] end)
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: merge_request_notes_plug(project.project_ref, merge_request_iid, identity, notes))

    conn =
      :get
      |> conn("/api/issues/#{issue.id}/merge_requests/#{merge_request_iid}/notes")
      |> assign_user(identity, project)

    conn = IssueController.merge_request_notes(conn, %{"id" => issue.id, "merge_request_iid" => to_string(merge_request_iid)})
    assert conn.status == 200
    assert [%{"body" => "Existing MR note", "id" => "gitlab-note-54"}] = Jason.decode!(conn.resp_body)["notes"]

    conn =
      :post
      |> conn("/api/issues/#{issue.id}/merge_requests/#{merge_request_iid}/notes")
      |> assign_user(identity, project)

    conn = IssueController.create_merge_request_note(conn, %{"id" => issue.id, "merge_request_iid" => to_string(merge_request_iid), "body" => "New MR note"})
    assert conn.status == 200
    assert [%{"body" => "Existing MR note"}, %{"body" => "New MR note"}] = Jason.decode!(conn.resp_body)["notes"]

    conn =
      :put
      |> conn("/api/issues/#{issue.id}/merge_requests/#{merge_request_iid}/notes/55")
      |> assign_user(identity, project)

    conn =
      IssueController.update_merge_request_note(conn, %{
        "id" => issue.id,
        "merge_request_iid" => to_string(merge_request_iid),
        "note_id" => "55",
        "body" => "Updated MR note"
      })

    assert conn.status == 200
    assert [%{"body" => "Existing MR note"}, %{"body" => "Updated MR note"}] = Jason.decode!(conn.resp_body)["notes"]

    conn =
      :delete
      |> conn("/api/issues/#{issue.id}/merge_requests/#{merge_request_iid}/notes/55")
      |> assign_user(identity, project)

    conn = IssueController.delete_merge_request_note(conn, %{"id" => issue.id, "merge_request_iid" => to_string(merge_request_iid), "note_id" => "55"})
    assert conn.status == 200
    assert [%{"body" => "Existing MR note"}] = Jason.decode!(conn.resp_body)["notes"]
  end

  test "submits merge request quick action commands as note text through user OAuth", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    merge_request_iid = 7

    Store.replace_project_merge_requests(project.id, [
      %{issue_id: issue.id, attrs: merge_request_attrs(merge_request_iid, "Implement drawer", "Closes ##{iid}")}
    ])

    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: merge_request_quick_action_note_plug(project.project_ref, merge_request_iid, identity))

    conn =
      :post
      |> conn("/api/issues/#{issue.id}/merge_requests/#{merge_request_iid}/notes")
      |> assign_user(identity, project)

    conn = IssueController.create_merge_request_note(conn, %{"id" => issue.id, "merge_request_iid" => to_string(merge_request_iid), "body" => "/ready "})
    assert conn.status == 200
    assert [%{"body" => "/ready "}] = Jason.decode!(conn.resp_body)["notes"]
  end

  test "updates an issue note through user OAuth", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    Store.upsert_note(issue.id, note_attrs(45, "Old body"))
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: note_update_plug(project.project_ref, iid, identity))

    conn =
      :put
      |> conn("/api/issues/#{issue.id}/notes/45")
      |> assign_user(identity, project)

    conn = IssueController.update_note(conn, %{"id" => issue.id, "note_id" => "45", "body" => "Updated body"})
    assert conn.status == 200

    [note] = Store.list_notes(issue.id)
    assert note.note_id == 45
    assert note.body == "Updated body"

    payload = Jason.decode!(conn.resp_body)
    assert [%{"body" => "Updated body"}] = payload["notes"]
  end

  test "deletes an issue note through user OAuth", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    Store.upsert_note(issue.id, note_attrs(45, "Delete me"))
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: note_delete_plug(project.project_ref, iid, identity))

    conn =
      :delete
      |> conn("/api/issues/#{issue.id}/notes/45")
      |> assign_user(identity, project)

    conn = IssueController.delete_note(conn, %{"id" => issue.id, "note_id" => "45"})
    assert conn.status == 200
    assert Store.list_notes(issue.id) == []

    payload = Jason.decode!(conn.resp_body)
    assert payload["notes"] == []
  end

  test "deletes already uploaded attachments when a later attachment upload fails", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    {:ok, calls} = Agent.start_link(fn -> [] end)
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: second_upload_failure_plug(project.project_ref, identity, calls))

    conn =
      :post
      |> conn("/api/issues/#{issue.id}/notes")
      |> assign_user(identity, project)

    conn =
      IssueController.create_note(conn, %{
        "id" => issue.id,
        "body" => "Two files",
        "files" => [
          plug_upload("first.txt", "first body", "text/plain"),
          plug_upload("second.txt", "second body", "text/plain")
        ]
      })

    assert conn.status == 422
    assert Agent.get(calls, & &1) == [:delete_first, :upload_second, :upload_first]
    assert Store.list_notes(issue.id) == []
  end

  test "deletes uploaded attachments when note creation is rejected by GitLab", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    {:ok, calls} = Agent.start_link(fn -> [] end)
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: note_create_failure_plug(project.project_ref, iid, identity, calls))
    upload = plug_upload("cleanup.txt", "temporary body", "text/plain")

    conn =
      :post
      |> conn("/api/issues/#{issue.id}/notes")
      |> assign_user(identity, project)

    conn = IssueController.create_note(conn, %{"id" => issue.id, "body" => "Will fail", "files" => upload})
    assert conn.status == 422
    assert Agent.get(calls, & &1) == [:delete_upload, :create_note, :upload]
  end

  test "keeps uploaded attachments when note creation result is ambiguous", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    {:ok, calls} = Agent.start_link(fn -> [] end)
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: ambiguous_note_failure_plug(project.project_ref, iid, identity, calls))
    upload = plug_upload("maybe-linked.txt", "temporary body", "text/plain")

    conn =
      :post
      |> conn("/api/issues/#{issue.id}/notes")
      |> assign_user(identity, project)

    conn = IssueController.create_note(conn, %{"id" => issue.id, "body" => "May have posted", "files" => upload})
    assert conn.status == 422
    assert Agent.get(calls, & &1) == [:create_note, :upload]
  end

  test "proxies only attachments referenced by the issue", %{identity: identity, iid: iid, project: project} do
    issue = seed_issue(iid, project)
    secret = "0123456789abcdef0123456789abcdef"
    Store.upsert_note(issue.id, note_attrs(45, "![proof](/uploads/#{secret}/proof.txt)"))
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: upload_proxy_plug(project.project_ref, iid, identity, secret))

    conn =
      :get
      |> conn("/api/issues/#{issue.id}/uploads/#{secret}/proof.txt")
      |> assign_user(identity, project)

    conn = IssueController.upload(conn, %{"id" => issue.id, "secret" => secret, "filename" => "proof.txt"})
    assert conn.status == 200
    assert conn.resp_body == "proxied attachment"
    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]

    conn =
      :get
      |> conn("/api/issues/#{issue.id}/uploads/#{secret}/other.txt")
      |> assign_user(identity, project)

    conn = IssueController.upload(conn, %{"id" => issue.id, "secret" => secret, "filename" => "other.txt"})
    assert conn.status == 404
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

  defp note_attachment_plug(project_ref, iid, identity) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      upload_path = "/api/v4/projects/#{project_ref}/uploads"
      notes_path = "/api/v4/projects/#{project_ref}/issues/#{iid}/notes"

      case {conn.method, conn.request_path} do
        {"POST", ^upload_path} ->
          assert %Plug.Upload{filename: "proof.txt", content_type: "text/plain"} = conn.body_params["file"]

          Req.Test.json(conn, %{
            "id" => 11,
            "alt" => "proof",
            "url" => "/uploads/0123456789abcdef0123456789abcdef/proof.txt",
            "markdown" => "![proof](/uploads/0123456789abcdef0123456789abcdef/proof.txt)"
          })

        {"POST", ^notes_path} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload["body"] =~ "/api/issues/"
          assert payload["body"] =~ "/uploads/0123456789abcdef0123456789abcdef/proof.txt"

          Req.Test.json(conn, raw_gitlab_note(99, payload["body"]))
      end
    end
  end

  defp note_update_plug(project_ref, iid, identity) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      assert conn.method == "PUT"
      assert conn.request_path == "/api/v4/projects/#{project_ref}/issues/#{iid}/notes/45"

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["body"] == "Updated body"

      Req.Test.json(conn, raw_gitlab_note(45, payload["body"]))
    end
  end

  defp note_delete_plug(project_ref, iid, identity) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      assert conn.method == "DELETE"
      assert conn.request_path == "/api/v4/projects/#{project_ref}/issues/#{iid}/notes/45"

      Plug.Conn.send_resp(conn, 204, "")
    end
  end

  defp merge_request_notes_plug(project_ref, merge_request_iid, identity, notes) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]

      notes_path = "/api/v4/projects/#{project_ref}/merge_requests/#{merge_request_iid}/notes"
      note_path = notes_path <> "/55"

      case {conn.method, conn.request_path} do
        {"GET", ^notes_path} ->
          Req.Test.json(conn, Agent.get(notes, & &1))

        {"POST", ^notes_path} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload["body"] == "New MR note"

          note = raw_gitlab_note(55, payload["body"])
          Agent.update(notes, &(&1 ++ [note]))
          Req.Test.json(conn, note)

        {"PUT", ^note_path} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload["body"] == "Updated MR note"

          note = raw_gitlab_note(55, payload["body"])
          Agent.update(notes, fn current -> Enum.map(current, &if(&1["id"] == 55, do: note, else: &1)) end)
          Req.Test.json(conn, note)

        {"DELETE", ^note_path} ->
          Agent.update(notes, &Enum.reject(&1, fn note -> note["id"] == 55 end))
          Plug.Conn.send_resp(conn, 204, "")
      end
    end
  end

  defp merge_request_update_plug(project_ref, merge_request_iid, identity) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      assert conn.method == "PUT"
      assert conn.request_path == "/api/v4/projects/#{project_ref}/merge_requests/#{merge_request_iid}"

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["title"] == "Updated MR"
      assert payload["description"] == "Updated description"
      assert payload["labels"] == "frontend,review"

      Req.Test.json(conn, %{
        "id" => 990_000 + merge_request_iid,
        "project_id" => 123,
        "iid" => merge_request_iid,
        "web_url" => "https://gitlab.example.com/group/project/-/merge_requests/#{merge_request_iid}",
        "title" => payload["title"],
        "description" => payload["description"],
        "state" => "opened",
        "draft" => false,
        "work_in_progress" => false,
        "source_branch" => "feature/mr-#{merge_request_iid}",
        "target_branch" => "main",
        "labels" => ["frontend", "review"],
        "assignees" => [],
        "reviewers" => [],
        "references" => %{"relative" => "!#{merge_request_iid}"}
      })
    end
  end

  defp merge_request_quick_action_note_plug(project_ref, merge_request_iid, identity) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      notes_path = "/api/v4/projects/#{project_ref}/merge_requests/#{merge_request_iid}/notes"

      case {conn.method, conn.request_path} do
        {"POST", ^notes_path} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload["body"] == "/ready "

          Req.Test.json(conn, raw_gitlab_note(55, payload["body"]))

        {"GET", ^notes_path} ->
          Req.Test.json(conn, [raw_gitlab_note(55, "/ready ")])
      end
    end
  end

  defp second_upload_failure_plug(project_ref, identity, calls) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      upload_path = "/api/v4/projects/#{project_ref}/uploads"
      delete_path = "/api/v4/projects/#{project_ref}/uploads/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/first.txt"

      case {conn.method, conn.request_path} do
        {"POST", ^upload_path} ->
          case conn.body_params["file"] do
            %Plug.Upload{filename: "first.txt"} ->
              Agent.update(calls, &[:upload_first | &1])

              Req.Test.json(conn, %{
                "id" => 21,
                "alt" => "first",
                "url" => "/uploads/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/first.txt",
                "markdown" => "[first](/uploads/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/first.txt)"
              })

            %Plug.Upload{filename: "second.txt"} ->
              Agent.update(calls, &[:upload_second | &1])

              conn
              |> Plug.Conn.put_status(500)
              |> Req.Test.json(%{message: "upload failed"})
          end

        {"DELETE", ^delete_path} ->
          Agent.update(calls, &[:delete_first | &1])
          Plug.Conn.send_resp(conn, 204, "")
      end
    end
  end

  defp note_create_failure_plug(project_ref, iid, identity, calls) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      upload_path = "/api/v4/projects/#{project_ref}/uploads"
      notes_path = "/api/v4/projects/#{project_ref}/issues/#{iid}/notes"
      delete_path = "/api/v4/projects/#{project_ref}/uploads/fedcba9876543210fedcba9876543210/cleanup.txt"

      case {conn.method, conn.request_path} do
        {"POST", ^upload_path} ->
          Agent.update(calls, &[:upload | &1])

          Req.Test.json(conn, %{
            "id" => 12,
            "alt" => "cleanup",
            "url" => "/uploads/fedcba9876543210fedcba9876543210/cleanup.txt",
            "markdown" => "[cleanup](/uploads/fedcba9876543210fedcba9876543210/cleanup.txt)"
          })

        {"POST", ^notes_path} ->
          Agent.update(calls, &[:create_note | &1])

          conn
          |> Plug.Conn.put_status(400)
          |> Req.Test.json(%{message: "body is invalid"})

        {"DELETE", ^delete_path} ->
          Agent.update(calls, &[:delete_upload | &1])
          Plug.Conn.send_resp(conn, 204, "")
      end
    end
  end

  defp ambiguous_note_failure_plug(project_ref, iid, identity, calls) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      upload_path = "/api/v4/projects/#{project_ref}/uploads"
      notes_path = "/api/v4/projects/#{project_ref}/issues/#{iid}/notes"
      delete_path = "/api/v4/projects/#{project_ref}/uploads/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee/maybe-linked.txt"

      case {conn.method, conn.request_path} do
        {"POST", ^upload_path} ->
          Agent.update(calls, &[:upload | &1])

          Req.Test.json(conn, %{
            "id" => 13,
            "alt" => "maybe-linked",
            "url" => "/uploads/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee/maybe-linked.txt",
            "markdown" => "[maybe-linked](/uploads/eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee/maybe-linked.txt)"
          })

        {"POST", ^notes_path} ->
          Agent.update(calls, &[:create_note | &1])

          conn
          |> Plug.Conn.put_status(500)
          |> Req.Test.json(%{message: "unknown if note was created"})

        {"DELETE", ^delete_path} ->
          Agent.update(calls, &[:delete_upload | &1])
          Plug.Conn.send_resp(conn, 204, "")
      end
    end
  end

  defp upload_proxy_plug(project_ref, iid, identity, secret) do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer oauth-token-#{identity.gitlab_user_id}"]
      notes_path = "/api/v4/projects/#{project_ref}/issues/#{iid}/notes"
      upload_path = "/api/v4/projects/#{project_ref}/uploads/#{secret}/proof.txt"

      case {conn.method, conn.request_path} do
        {"GET", ^notes_path} ->
          Req.Test.json(conn, [])

        {"GET", ^upload_path} ->
          conn
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.send_resp(200, "proxied attachment")
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

  defp note_attrs(note_id, body) do
    %{
      note_id: note_id,
      body: body,
      system: false,
      internal: false,
      resolvable: false,
      gitlab_created_at: nil,
      gitlab_updated_at: nil,
      author: %{name: "Developer", username: "dev"}
    }
  end

  defp raw_gitlab_note(note_id, body) do
    %{
      "id" => note_id,
      "body" => body,
      "system" => false,
      "internal" => false,
      "resolvable" => false,
      "author" => %{"name" => "Developer", "username" => "dev"}
    }
  end

  defp merge_request_attrs(iid, title, description) do
    %{
      merge_request_id: 990_000 + iid,
      iid: iid,
      title: title,
      description: description,
      state: "opened",
      draft: false,
      work_in_progress: false,
      web_url: "https://gitlab.example.com/group/project/-/merge_requests/#{iid}",
      source_branch: "feature/mr-#{iid}",
      target_branch: "main",
      merge_status: "can_be_merged",
      detailed_merge_status: "mergeable",
      labels: ["frontend"],
      author: %{id: 5, name: "Developer", username: "dev"},
      assignees: [],
      reviewers: [],
      references: %{relative: "!#{iid}", full: "group/project!#{iid}"},
      user_notes_count: 1,
      upvotes: 0,
      downvotes: 0,
      changes_count: "3",
      raw_gitlab: %{"description" => description}
    }
  end

  defp plug_upload(filename, body, content_type) do
    path = Path.join(System.tmp_dir!(), "symphony-#{System.unique_integer([:positive])}-#{filename}")
    File.write!(path, body)
    %Plug.Upload{path: path, filename: filename, content_type: content_type}
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
