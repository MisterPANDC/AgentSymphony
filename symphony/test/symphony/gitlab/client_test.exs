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

  defp config do
    %Config{
      gitlab_base_url: "https://gitlab.example.com",
      gitlab_api_root: "https://gitlab.example.com/api/v4",
      gitlab_project_ref: "123",
      gitlab_project_path_param: "123",
      token: "test-token",
      source: :split_config,
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
end
