defmodule Symphony.GitLab.IssueMapperTest do
  use ExUnit.Case, async: true

  alias Symphony.GitLab.IssueMapper

  test "maps GitLab issue id and iid distinctly" do
    attrs =
      IssueMapper.from_gitlab(%{
        "id" => 9001,
        "project_id" => 42,
        "iid" => 7,
        "web_url" => "https://gitlab.example.com/group/project/-/issues/7",
        "title" => "Fix sync",
        "description" => "Long\n\nbody",
        "state" => "opened",
        "labels" => ["bug"],
        "assignees" => [%{"id" => 1, "username" => "yifei", "name" => "Yifei"}]
      })

    assert attrs.gitlab_issue_id == 9001
    assert attrs.iid == 7
    assert attrs.identifier == "GL-7"
    assert attrs.labels == ["bug"]
  end
end
