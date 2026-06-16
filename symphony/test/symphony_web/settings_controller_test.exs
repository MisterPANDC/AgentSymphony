defmodule SymphonyElixirWeb.SettingsControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias SymphonyElixir.Store
  alias SymphonyElixirWeb.SettingsController

  setup do
    unique = System.unique_integer([:positive])

    project =
      Store.upsert_project(%{
        api_root: "https://gitlab.example.com/api/v4",
        project_ref: "group/project-#{unique}",
        project_id: 920_000 + unique,
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

    {:ok, identity: identity, project: project, unique: unique}
  end

  test "updates and clears the current project's local repo path", %{identity: identity, project: project, unique: unique} do
    repo = Path.join(System.tmp_dir!(), "symphony-settings-controller-repo-#{unique}")
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:group/project-#{unique}.git"], cd: repo)

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
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-repo-#{unique}"))
  end

  test "rejects a local repo path that is not a git repository", %{identity: identity, project: project, unique: unique} do
    directory = Path.join(System.tmp_dir!(), "symphony-settings-controller-not-git-#{unique}")
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
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-not-git-#{unique}"))
  end

  test "rejects a git repository from a different GitLab project", %{identity: identity, project: project, unique: unique} do
    repo = Path.join(System.tmp_dir!(), "symphony-settings-controller-wrong-repo-#{unique}")
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
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-wrong-repo-#{unique}"))
  end

  test "scans nearby local repositories for the current project", %{identity: identity, project: project, unique: unique} do
    root = Path.join(System.tmp_dir!(), "symphony-settings-controller-scan-#{unique}")
    symphony_dir = Path.join(root, "symphony")
    repo = Path.join(root, "project-#{unique}")
    File.mkdir_p!(symphony_dir)
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:group/project-#{unique}.git"], cd: repo)

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
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-scan-#{unique}"))
  end

  test "scans wider local folders when requested", %{identity: identity, project: project, unique: unique} do
    root = Path.join(System.tmp_dir!(), "symphony-settings-controller-local-scan-#{unique}")
    symphony_dir = Path.join(root, "symphony")
    repo = Path.join([root, "archives", "team", "project-#{unique}"])
    File.mkdir_p!(symphony_dir)
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:group/project-#{unique}.git"], cd: repo)

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
    File.rm_rf(Path.join(System.tmp_dir!(), "symphony-settings-controller-local-scan-#{unique}"))
  end

  defp assign_user(conn, identity, project) do
    Plug.Conn.assign(conn, :current_user, %{
      identity_id: identity.id,
      gitlab_user_id: identity.gitlab_user_id,
      username: identity.username,
      project_setting_id: project.id,
      access_level: 50
    })
  end

  defp canonical_path!(path) do
    {canonical, 0} = System.cmd("pwd", ["-P"], cd: path)
    String.trim(canonical)
  end
end
