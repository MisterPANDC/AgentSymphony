defmodule Symphony.GitLab.ConfigTest do
  use ExUnit.Case, async: true

  alias Symphony.GitLab.Config

  test "builds numeric project config from selected repository" do
    assert {:ok, config} =
             Config.from_project_setting(%{
               api_root: "https://gitlab.example.com/api/v4",
               project_ref: "123"
             })

    assert config.gitlab_base_url == "https://gitlab.example.com"
    assert config.gitlab_api_root == "https://gitlab.example.com/api/v4"
    assert config.gitlab_project_ref == "123"
    assert config.gitlab_project_path_param == "123"
    assert config.source == :project_setting
  end

  test "encodes selected repository path for GitLab project path parameter" do
    assert {:ok, config} =
             Config.from_project_setting(%{
               api_root: "https://gitlab.example.com/api/v4",
               project_ref: "my-group/project"
             })

    assert config.gitlab_project_ref == "my-group/project"
    assert config.gitlab_project_path_param == "my-group%2Fproject"
  end

  test "rejects incomplete selected repository config" do
    assert {:error, error} = Config.from_project_setting(%{api_root: "https://gitlab.example.com/api/v4"})
    assert error.type == :invalid_config
  end
end
