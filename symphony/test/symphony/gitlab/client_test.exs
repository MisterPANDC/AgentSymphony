defmodule Symphony.GitLab.ClientTest do
  use ExUnit.Case, async: false

  alias Symphony.GitLab.{Client, Config, Error}

  setup do
    Application.delete_env(:symphony_elixir, :gitlab_req_options)

    on_exit(fn ->
      Application.delete_env(:symphony_elixir, :gitlab_req_options)
    end)

    :ok
  end

  test "follows GitLab Link pagination headers" do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: pagination_plug())

    assert {:ok, issues} = Client.list_project_issues(config(), per_page: 2, state: "all")
    assert Enum.map(issues, & &1["iid"]) == [1, 2]
  end

  test "normalizes GitLab API errors without leaking token" do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: error_plug())

    assert {:error, %Error{} = error} = Client.get_project_issue(config(), 1)
    assert error.type == :unauthorized
    assert error.status == 401
    assert error.message == "bad token"
  end

  test "creates a project issue with scoped attributes" do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: create_issue_plug())

    assert {:ok, issue} =
             Client.create_project_issue(config(), %{
               "title" => "Follow-up",
               "description" => "Body",
               "labels" => "follow-up,backend"
             })

    assert issue["iid"] == 3
    assert issue["title"] == "Follow-up"
  end

  test "updates a project merge request with scoped attributes" do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: merge_request_update_plug())

    assert {:ok, merge_request} =
             Client.update_project_merge_request(config(), 7, %{
               "title" => "Updated MR",
               "description" => "Updated body",
               "labels" => "frontend,review"
             })

    assert merge_request["iid"] == 7
    assert merge_request["title"] == "Updated MR"
    assert merge_request["labels"] == ["frontend", "review"]
  end

  test "updates and deletes issue notes" do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: note_update_plug())

    assert {:ok, note} = Client.update_issue_note(config(), 3, 44, "Updated body")
    assert note["id"] == 44
    assert note["body"] == "Updated body"
    assert :ok = Client.delete_issue_note(config(), 3, 44)
  end

  test "lists, creates, updates, and deletes merge request notes" do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: merge_request_note_plug())

    assert {:ok, [note]} = Client.list_merge_request_notes(config(), 7, per_page: 1)
    assert note["body"] == "Existing MR note"

    assert {:ok, note} = Client.create_merge_request_note(config(), 7, "New MR note")
    assert note["id"] == 55
    assert note["body"] == "New MR note"

    assert {:ok, note} = Client.update_merge_request_note(config(), 7, 55, "Updated MR note")
    assert note["id"] == 55
    assert note["body"] == "Updated MR note"

    assert :ok = Client.delete_merge_request_note(config(), 7, 55)
  end

  test "uploads and downloads project markdown uploads" do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: upload_plug())
    path = Path.join(System.tmp_dir!(), "symphony-upload-client-test.txt")
    File.write!(path, "attachment body")

    assert {:ok, upload} = Client.upload_project_file(config(), %{path: path, filename: "proof.txt", content_type: "text/plain"})
    assert upload["markdown"] == "[proof](/uploads/0123456789abcdef0123456789abcdef/proof.txt)"

    assert {:ok, downloaded} = Client.download_project_upload(config(), "0123456789abcdef0123456789abcdef", "proof.txt")
    assert downloaded.body == "downloaded attachment"
    assert downloaded.content_type =~ "text/plain"
  end

  defp config do
    %Config{
      gitlab_base_url: "https://gitlab.example.com",
      gitlab_api_root: "https://gitlab.example.com/api/v4",
      gitlab_project_ref: "123",
      gitlab_project_path_param: "123",
      token: "test-token",
      source: :project_setting,
      sync_page_size: 2
    }
  end

  defp pagination_plug do
    fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]

      case {conn.request_path, conn.query_params["page"] || "1"} do
        {"/api/v4/projects/123/issues", "1"} ->
          conn
          |> Plug.Conn.put_resp_header("link", ~s(<https://gitlab.example.com/api/v4/projects/123/issues?page=2>; rel="next"))
          |> Req.Test.json([%{iid: 1}])

        {"/api/v4/projects/123/issues", "2"} ->
          Req.Test.json(conn, [%{iid: 2}])
      end
    end
  end

  defp error_plug do
    fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{message: "bad token"})
    end
  end

  defp create_issue_plug do
    fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/v4/projects/123/issues"
      assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["title"] == "Follow-up"
      assert payload["description"] == "Body"
      assert payload["labels"] == "follow-up,backend"

      Req.Test.json(conn, %{
        "id" => 300,
        "project_id" => 123,
        "iid" => 3,
        "web_url" => "https://gitlab.example.com/group/project/-/issues/3",
        "title" => payload["title"],
        "description" => payload["description"],
        "state" => "opened",
        "labels" => ["follow-up", "backend"],
        "assignees" => []
      })
    end
  end

  defp note_update_plug do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]

      case {conn.method, conn.request_path} do
        {"PUT", "/api/v4/projects/123/issues/3/notes/44"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload["body"] == "Updated body"

          Req.Test.json(conn, %{
            "id" => 44,
            "body" => payload["body"],
            "system" => false,
            "internal" => false,
            "author" => %{"name" => "Developer", "username" => "dev"}
          })

        {"DELETE", "/api/v4/projects/123/issues/3/notes/44"} ->
          Plug.Conn.send_resp(conn, 204, "")
      end
    end
  end

  defp merge_request_update_plug do
    fn conn ->
      assert conn.method == "PUT"
      assert conn.request_path == "/api/v4/projects/123/merge_requests/7"
      assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]

      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert payload["title"] == "Updated MR"
      assert payload["description"] == "Updated body"
      assert payload["labels"] == "frontend,review"

      Req.Test.json(conn, %{
        "id" => 700,
        "project_id" => 123,
        "iid" => 7,
        "web_url" => "https://gitlab.example.com/group/project/-/merge_requests/7",
        "title" => payload["title"],
        "description" => payload["description"],
        "state" => "opened",
        "draft" => false,
        "work_in_progress" => false,
        "source_branch" => "feature",
        "target_branch" => "main",
        "labels" => ["frontend", "review"]
      })
    end
  end

  defp merge_request_note_plug do
    fn conn ->
      assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]

      case {conn.method, conn.request_path} do
        {"GET", "/api/v4/projects/123/merge_requests/7/notes"} ->
          Req.Test.json(conn, [
            %{
              "id" => 54,
              "body" => "Existing MR note",
              "system" => false,
              "internal" => false,
              "author" => %{"name" => "Developer", "username" => "dev"}
            }
          ])

        {"POST", "/api/v4/projects/123/merge_requests/7/notes"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload["body"] == "New MR note"

          Req.Test.json(conn, %{
            "id" => 55,
            "body" => payload["body"],
            "system" => false,
            "internal" => false,
            "author" => %{"name" => "Developer", "username" => "dev"}
          })

        {"PUT", "/api/v4/projects/123/merge_requests/7/notes/55"} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          payload = Jason.decode!(body)
          assert payload["body"] == "Updated MR note"

          Req.Test.json(conn, %{
            "id" => 55,
            "body" => payload["body"],
            "system" => false,
            "internal" => false,
            "author" => %{"name" => "Developer", "username" => "dev"}
          })

        {"DELETE", "/api/v4/projects/123/merge_requests/7/notes/55"} ->
          Plug.Conn.send_resp(conn, 204, "")
      end
    end
  end

  defp upload_plug do
    fn conn ->
      case {conn.method, conn.request_path} do
        {"POST", "/api/v4/projects/123/uploads"} ->
          assert Plug.Conn.get_req_header(conn, "private-token") == ["test-token"]
          assert %Plug.Upload{filename: "proof.txt", content_type: "text/plain"} = conn.body_params["file"]

          Req.Test.json(conn, %{
            "id" => 5,
            "alt" => "proof",
            "url" => "/uploads/0123456789abcdef0123456789abcdef/proof.txt",
            "full_path" => "/-/project/123/uploads/0123456789abcdef0123456789abcdef/proof.txt",
            "markdown" => "[proof](/uploads/0123456789abcdef0123456789abcdef/proof.txt)"
          })

        {"GET", "/api/v4/projects/123/uploads/0123456789abcdef0123456789abcdef/proof.txt"} ->
          conn
          |> Plug.Conn.put_resp_content_type("text/plain")
          |> Plug.Conn.send_resp(200, "downloaded attachment")
      end
    end
  end
end
