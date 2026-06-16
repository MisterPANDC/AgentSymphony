defmodule SymphonyElixir.LocalRepoTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.LocalRepo

  test "validates a local git repository path" do
    root = tmp_path("valid")
    repo = Path.join(root, "project")
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)

    assert {:ok, result} = LocalRepo.validate_path(repo)
    assert result.path == realpath!(repo)
    assert result.git_root == realpath!(repo)
  after
    File.rm_rf(tmp_path("valid"))
  end

  test "rejects missing and non-git directories" do
    root = tmp_path("invalid")
    File.mkdir_p!(root)

    assert {:error, :local_repo_path_not_found} = LocalRepo.validate_path(Path.join(root, "missing"))
    assert {:error, :not_a_git_repository} = LocalRepo.validate_path(root)
  after
    File.rm_rf(tmp_path("invalid"))
  end

  test "validates that a repo origin matches the selected project" do
    root = tmp_path("project-match")
    repo = Path.join(root, "project")
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:group/project.git"], cd: repo)

    project = %{path_with_namespace: "group/project", web_url: "https://gitlab.example.com/group/project"}
    wrong_project = %{path_with_namespace: "other/project", web_url: "https://gitlab.example.com/other/project"}

    assert {:ok, result} = LocalRepo.validate_project_path(repo, project)
    assert result.path == realpath!(repo)
    assert {:error, :local_repo_project_mismatch} = LocalRepo.validate_project_path(repo, wrong_project)
  after
    File.rm_rf(tmp_path("project-match"))
  end

  test "accepts ssh origin URLs when the path and host match the selected project" do
    root = tmp_path("ssh-project-match")
    repo = Path.join(root, "project")
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "ssh://git@gitlab.example.com/group/project.git"], cd: repo)

    project = %{path_with_namespace: "group/project", web_url: "https://gitlab.example.com/group/project"}

    assert {:ok, result} = LocalRepo.validate_project_path(repo, project)
    assert result.path == realpath!(repo)
  after
    File.rm_rf(tmp_path("ssh-project-match"))
  end

  test "discovers nearby candidates by selected project name" do
    root = tmp_path("scan")
    symphony_dir = Path.join(root, "symphony")
    repo = Path.join(root, "project")
    File.mkdir_p!(symphony_dir)
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:group/project.git"], cd: repo)

    project = %{path_with_namespace: "group/project", project_ref: "group/project", name: "Project"}

    File.cd!(symphony_dir, fn ->
      assert [%{path: path, score: 100} | _] = LocalRepo.candidates(project)
      assert path == realpath!(repo)
    end)
  after
    File.rm_rf(tmp_path("scan"))
  end

  test "wider local search discovers matching repos below local project folders" do
    root = tmp_path("local-scan")
    symphony_dir = Path.join(root, "symphony")
    repo = Path.join([root, "archives", "team", "project"])
    File.mkdir_p!(symphony_dir)
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:group/project.git"], cd: repo)

    project = %{path_with_namespace: "group/project", project_ref: "group/project", name: "Project"}

    File.cd!(symphony_dir, fn ->
      assert [] = LocalRepo.candidates(project)
      assert [%{path: path, score: 90, reason: reason} | _] = LocalRepo.candidates(project, scope: :local)
      assert path == realpath!(repo)
      assert reason =~ "wider local search"
    end)
  after
    File.rm_rf(tmp_path("local-scan"))
  end

  test "does not suggest a nearby repo whose origin belongs to another project" do
    root = tmp_path("wrong-scan")
    symphony_dir = Path.join(root, "symphony")
    repo = Path.join(root, "project")
    File.mkdir_p!(symphony_dir)
    File.mkdir_p!(repo)
    assert {"", 0} = System.cmd("git", ["init", "--quiet"], cd: repo)
    assert {"", 0} = System.cmd("git", ["remote", "add", "origin", "git@gitlab.example.com:other/project.git"], cd: repo)

    project = %{path_with_namespace: "group/project", project_ref: "group/project", name: "Project"}

    File.cd!(symphony_dir, fn ->
      assert [] = LocalRepo.candidates(project)
    end)
  after
    File.rm_rf(tmp_path("wrong-scan"))
  end

  defp realpath!(path) do
    {realpath, 0} = System.cmd("pwd", ["-P"], cd: path)
    String.trim(realpath)
  end

  defp tmp_path(name) do
    Path.join(System.tmp_dir!(), "symphony-local-repo-test-#{name}")
  end
end
