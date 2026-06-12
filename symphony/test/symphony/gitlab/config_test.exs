defmodule Symphony.GitLab.ConfigTest do
  use ExUnit.Case, async: true

  alias Symphony.GitLab.Config

  test "parses numeric project API URL" do
    assert {:ok, config} = Config.parse_project_api_url("https://gitlab.example.com/api/v4/projects/123")
    assert config.gitlab_base_url == "https://gitlab.example.com"
    assert config.gitlab_api_root == "https://gitlab.example.com/api/v4"
    assert config.gitlab_project_ref == "123"
    assert config.gitlab_project_path_param == "123"
  end

  test "parses encoded project path API URL" do
    assert {:ok, config} = Config.parse_project_api_url("https://gitlab.example.com/api/v4/projects/my-group%2Fproject")
    assert config.gitlab_project_ref == "my-group/project"
    assert config.gitlab_project_path_param == "my-group%2Fproject"
  end

  test "split project path encodes slash for GitLab project path parameter" do
    assert {:ok, config} = Config.from_split_config("https://gitlab.example.com", "my-group/project")
    assert config.gitlab_project_path_param == "my-group%2Fproject"
  end

  test "redacts token from strings" do
    previous = System.get_env("GITLAB_TOKEN")
    System.put_env("GITLAB_TOKEN", "secret-token")
    on_exit(fn -> restore_env("GITLAB_TOKEN", previous) end)

    assert Config.redact("PRIVATE-TOKEN secret-token") == "PRIVATE-TOKEN [REDACTED]"
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
