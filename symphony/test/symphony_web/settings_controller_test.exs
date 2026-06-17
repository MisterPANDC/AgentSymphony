defmodule SymphonyElixirWeb.SettingsControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias SymphonyElixir.Store
  alias SymphonyElixirWeb.SettingsController

  setup do
    {:ok, _started} = Application.ensure_all_started(:symphony_elixir)
    reset_json_store()

    previous_secret = System.get_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET")
    System.put_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", "settings-controller-test-secret")
    Application.delete_env(:symphony_elixir, :gitlab_req_options)

    unique = System.unique_integer([:positive])
    project_ref = "lfm/settings-#{unique}"

    project =
      Store.upsert_project(%{
        api_root: "https://gitlab.example.com/api/v4",
        project_ref: project_ref,
        project_id: 900_000 + unique,
        path_with_namespace: project_ref,
        name: "Settings #{unique}",
        web_url: "https://gitlab.example.com/#{project_ref}",
        visibility: "private"
      })

    identity =
      Store.upsert_gitlab_identity(%{
        issuer: "https://gitlab.example.com",
        gitlab_user_id: to_string(unique),
        sub: "user-#{unique}",
        username: "dev-#{unique}"
      })

    on_exit(fn ->
      restore_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET", previous_secret)
      Application.delete_env(:symphony_elixir, :gitlab_req_options)
    end)

    {:ok, identity: identity, project: project, project_ref: project_ref}
  end

  test "explains service account project 404 as an access problem", %{identity: identity, project: project, project_ref: project_ref} do
    Application.put_env(:symphony_elixir, :gitlab_req_options, plug: project_not_found_plug(project_ref))

    conn =
      :put
      |> conn("/api/settings/gitlab/service-account-token")
      |> assign_user(identity, project)

    conn = SettingsController.update_service_account_token(conn, %{"serviceAccountToken" => "service-token"})

    assert conn.status == 422

    payload = Jason.decode!(conn.resp_body)
    assert payload["error"]["type"] == "service_account_project_access_denied"
    assert payload["error"]["status"] == 404
    assert payload["error"]["message"] =~ "cannot see #{project_ref}"
    assert payload["error"]["message"] =~ "GitLab may return 404"
    assert payload["error"]["message"] =~ "Add the Service Account user to the project or its group"
    assert Store.service_account_credential(project.api_root) == nil
  end

  test "updates and clears the current project's local repo path", %{identity: identity, project: project, project_ref: project_ref} do
    repo = Path.join(System.tmp_dir!(), "symphony-settings-controller-repo-#{project.id}")
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:#{project_ref}.git"], cd: repo)

    conn =
      :put
      |> conn("/api/settings/gitlab/local-repo")
      |> assign_user(identity, project)

    conn = SettingsController.update_local_repo(conn, %{"localRepoPath" => repo})
    assert conn.status == 200
    payload = Jason.decode!(conn.resp_body)
    assert payload["project"]["local_repo_path"] == canonical_path!(repo)

    conn =
      :put
      |> conn("/api/settings/gitlab/local-repo")
      |> assign_user(identity, project)

    conn = SettingsController.update_local_repo(conn, %{"localRepoPath" => ""})
    assert conn.status == 200
    payload = Jason.decode!(conn.resp_body)
    assert is_nil(payload["project"]["local_repo_path"])
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-repo-#{project.id}"))
  end

  test "rejects a local repo path that is not a git repository", %{identity: identity, project: project} do
    directory = Path.join(System.tmp_dir!(), "symphony-settings-controller-not-git-#{project.id}")
    File.mkdir_p!(directory)

    conn =
      :put
      |> conn("/api/settings/gitlab/local-repo")
      |> assign_user(identity, project)

    conn = SettingsController.update_local_repo(conn, %{"localRepoPath" => directory})
    assert conn.status == 422
    payload = Jason.decode!(conn.resp_body)
    assert payload["error"]["type"] == "not_a_git_repository"
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-not-git-#{project.id}"))
  end

  test "rejects a git repository from a different GitLab project", %{identity: identity, project: project} do
    repo = Path.join(System.tmp_dir!(), "symphony-settings-controller-wrong-repo-#{project.id}")
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:other/project.git"], cd: repo)

    conn =
      :put
      |> conn("/api/settings/gitlab/local-repo")
      |> assign_user(identity, project)

    conn = SettingsController.update_local_repo(conn, %{"localRepoPath" => repo})
    assert conn.status == 422
    payload = Jason.decode!(conn.resp_body)
    assert payload["error"]["type"] == "local_repo_project_mismatch"
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-wrong-repo-#{project.id}"))
  end

  test "scans nearby local repositories for the current project", %{identity: identity, project: project, project_ref: project_ref} do
    root = Path.join(System.tmp_dir!(), "symphony-settings-controller-scan-#{project.id}")
    symphony_dir = Path.join(root, "symphony")
    repo = Path.join(root, Path.basename(project_ref))
    File.mkdir_p!(symphony_dir)
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:#{project_ref}.git"], cd: repo)

    conn =
      :get
      |> conn("/api/settings/gitlab/local-repo/candidates")
      |> assign_user(identity, project)

    conn =
      File.cd!(symphony_dir, fn ->
        SettingsController.local_repo_candidates(conn, %{})
      end)

    assert conn.status == 200
    payload = Jason.decode!(conn.resp_body)
    assert [%{"path" => path, "score" => 100} | _] = payload["candidates"]
    assert path == canonical_path!(repo)
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-scan-#{project.id}"))
  end

  test "scans wider local folders when requested", %{identity: identity, project: project, project_ref: project_ref} do
    root = Path.join(System.tmp_dir!(), "symphony-settings-controller-local-scan-#{project.id}")
    symphony_dir = Path.join(root, "symphony")
    repo = Path.join([root, "archives", "team", Path.basename(project_ref)])
    File.mkdir_p!(symphony_dir)
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:#{project_ref}.git"], cd: repo)

    conn =
      :get
      |> conn("/api/settings/gitlab/local-repo/candidates?scope=local")
      |> assign_user(identity, project)

    conn =
      File.cd!(symphony_dir, fn ->
        SettingsController.local_repo_candidates(conn, %{"scope" => "local"})
      end)

    assert conn.status == 200
    payload = Jason.decode!(conn.resp_body)
    assert [%{"path" => path, "score" => 90, "reason" => reason} | _] = payload["candidates"]
    assert path == canonical_path!(repo)
    assert reason =~ "wider local search"
  after
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-local-scan-#{project.id}"))
  end

  defp project_not_found_plug(project_ref) do
    encoded_ref = URI.encode(project_ref, &URI.char_unreserved?/1)

    fn conn ->
      assert conn.method == "GET"
      assert conn.request_path == "/api/v4/projects/#{encoded_ref}"
      assert Plug.Conn.get_req_header(conn, "private-token") == ["service-token"]

      conn
      |> Plug.Conn.put_status(404)
      |> Req.Test.json(%{message: "404 Project Not Found"})
    end
  end

  defp assign_user(conn, identity, project) do
    Plug.Conn.assign(conn, :current_user, %{
      identity_id: identity.id,
      gitlab_user_id: identity.gitlab_user_id,
      username: identity.username,
      project_setting_id: project.id,
      access_level: 40
    })
  end

  defp reset_json_store do
    if Store.configured_backend() == :json and Process.whereis(SymphonyElixir.Store.Json) do
      :sys.replace_state(SymphonyElixir.Store.Json, fn state ->
        %{
          state
          | project: nil,
            projects: %{},
            identities: %{},
            oauth_tokens: %{},
            service_account_credentials: %{},
            project_memberships: %{},
            issues: %{},
            issue_order: [],
            issue_by_iid: %{},
            issue_by_gitlab_id: %{},
            workflow_states: %{},
            dependencies: %{},
            relations: %{},
            notes: %{},
            merge_requests: %{},
            events: [],
            cursors: %{},
            runs: %{},
            run_order: [],
            run_events: %{},
            runtime_blocks: %{}
        }
      end)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp canonical_path!(path) do
    {canonical, 0} = System.cmd("pwd", ["-P"], cd: path)
    String.trim(canonical)
  end
end
