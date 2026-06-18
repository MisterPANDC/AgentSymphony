defmodule SymphonyElixirWeb.AgentControllerTest do
  use ExUnit.Case, async: false

  import Plug.Test

  alias SymphonyElixir.Store
  alias SymphonyElixirWeb.AgentController

  setup do
    {:ok, _started} = Application.ensure_all_started(:symphony_elixir)
    reset_json_store()
    previous_path = System.get_env("PATH")
    previous_home = System.get_env("SYMPHONY_HOME")
    home = Path.join(System.tmp_dir!(), "symphony-agent-controller-home-#{System.unique_integer([:positive])}")
    System.put_env("SYMPHONY_HOME", home)
    bin_dir = Path.join(System.tmp_dir!(), "symphony-agent-controller-bin-#{System.unique_integer([:positive])}")
    File.mkdir_p!(bin_dir)
    codex_path = Path.join(bin_dir, "codex")

    File.write!(codex_path, """
    #!/bin/sh
    if [ "$1" = "mcp" ] && [ "$2" = "list" ]; then
      printf '[]\\n'
      exit 0
    fi
    if [ "$1" = "login" ]; then
      printf 'login started\\n'
      exit 0
    fi
    exit 0
    """)

    File.chmod!(codex_path, 0o755)
    System.put_env("PATH", [bin_dir, previous_path] |> Enum.reject(&is_nil/1) |> Enum.join(":"))

    on_exit(fn ->
      restore_env("PATH", previous_path)
      restore_env("SYMPHONY_HOME", previous_home)
      File.rm_rf(bin_dir)
      File.rm_rf(home)
    end)

    {:ok, home: home}
  end

  test "deletes a registered agent" do
    {:ok, agent} = Store.create_registered_agent(agent_attrs("delete"))

    conn =
      :delete
      |> conn("/api/agents/#{agent.id}")

    conn = AgentController.delete(conn, %{"id" => agent.id})
    assert conn.status == 200

    payload = Jason.decode!(conn.resp_body)
    assert payload["agent"]["id"] == agent.id
    assert Store.list_registered_agents() == []
  end

  test "returns 404 when deleting a missing registered agent" do
    conn =
      :delete
      |> conn("/api/agents/missing-agent")

    conn = AgentController.delete(conn, %{"id" => "missing-agent"})
    assert conn.status == 404

    payload = Jason.decode!(conn.resp_body)
    assert payload["error"]["type"] == "agent_not_found"
  end

  test "updates a registered agent name and mcp selection" do
    conn =
      :post
      |> conn("/api/agents/mcp")

    AgentController.create_mcp(conn, %{
      "mcpServers" => %{
        "playwright" => %{"command" => "npx", "args" => ["@playwright/mcp"], "env" => %{}}
      }
    })

    {:ok, agent} = Store.create_registered_agent(agent_attrs("settings"))

    conn =
      :patch
      |> conn("/api/agents/#{agent.id}")

    conn = AgentController.update(conn, %{"id" => agent.id, "name" => "Renamed Codex", "mcpServerNames" => ["playwright"]})
    assert conn.status == 200

    payload = Jason.decode!(conn.resp_body)
    assert payload["agent"]["name"] == "Renamed Codex"
    assert payload["agent"]["mcpServerNames"] == ["playwright"]
  end

  test "starts subscription relogin for a registered agent" do
    {:ok, agent} = Store.create_registered_agent(agent_attrs("relogin"))

    conn =
      :post
      |> conn("/api/agents/#{agent.id}/login")

    conn = AgentController.login(conn, %{"id" => agent.id})
    assert conn.status == 200

    payload = Jason.decode!(conn.resp_body)
    assert payload["agent"]["id"] == agent.id
    assert payload["agent"]["credentialStatus"] == "login_started"
    assert payload["login"]["command"] =~ "codex login"
    assert is_binary(payload["login"]["startedAt"])
  end

  test "saves agent asset registry", %{home: home} do
    skill_dir = Path.join(home, "source-skill")
    plugin_dir = Path.join(home, "source-plugin")
    File.mkdir_p!(skill_dir)
    File.mkdir_p!(plugin_dir)

    conn =
      :post
      |> conn("/api/agents/assets")

    conn =
      AgentController.create_assets(conn, %{
        "skills" => %{"review" => %{"path" => skill_dir}},
        "plugins" => %{"github" => %{"path" => plugin_dir}}
      })

    assert conn.status == 200
    payload = Jason.decode!(conn.resp_body)
    assert payload["assets"]["pluginPath"] == Path.join(home, "agent-plugin.json")
    assert payload["assets"]["skillPath"] == Path.join(home, "agent-skill.json")
    assert payload["assets"]["skills"]["review"]["path"] == skill_dir
    assert payload["assets"]["plugins"]["github"]["path"] == plugin_dir

    assert Jason.decode!(File.read!(Path.join(home, "agent-skill.json"))) == %{"review" => %{"path" => skill_dir}}
    assert Jason.decode!(File.read!(Path.join(home, "agent-plugin.json"))) == %{"github" => %{"path" => plugin_dir}}
  end

  test "saves plugin git URL and installs markdown skill" do
    conn =
      :post
      |> conn("/api/agents/assets")

    conn =
      AgentController.create_assets(conn, %{
        "skills" => %{"review" => %{"content" => "# Review\n\nCheck the code.\n", "filename" => "review.md"}},
        "plugins" => %{"github" => %{"git_url" => "https://github.com/example/plugin.git"}}
      })

    assert conn.status == 200
    payload = Jason.decode!(conn.resp_body)
    assert payload["assets"]["skills"]["review"]["content"] =~ "Check the code"
    assert payload["assets"]["plugins"]["github"]["git_url"] == "https://github.com/example/plugin.git"

    {:ok, agent} = Store.create_registered_agent(agent_attrs("markdown-skill"))

    conn =
      :post
      |> conn("/api/agents/#{agent.id}/assets/skills/review")

    conn = AgentController.install_asset(conn, %{"id" => agent.id, "kind" => "skills", "name" => "review"})
    assert conn.status == 200

    skill_target = Path.join([agent.codex_home, "skills", "review"])
    wait_until(fn -> File.exists?(Path.join(skill_target, "SKILL.md")) end)
    assert File.read!(Path.join(skill_target, "SKILL.md")) =~ "Check the code"
  end

  test "installs and removes a skill for a specific agent", %{home: home} do
    skill_dir = Path.join(home, "review-skill")
    File.mkdir_p!(skill_dir)

    conn =
      :post
      |> conn("/api/agents/assets")

    AgentController.create_assets(conn, %{"skills" => %{"review" => %{"path" => skill_dir}}, "plugins" => %{}})
    {:ok, agent} = Store.create_registered_agent(agent_attrs("asset"))

    conn =
      :post
      |> conn("/api/agents/#{agent.id}/assets/skills/review")

    conn = AgentController.install_asset(conn, %{"id" => agent.id, "kind" => "skills", "name" => "review"})
    assert conn.status == 200
    payload = Jason.decode!(conn.resp_body)
    assert payload["agent"]["skillNames"] == ["review"]

    skill_target = Path.join([agent.codex_home, "skills", "review"])
    wait_until(fn -> match?({:ok, %File.Stat{type: :symlink}}, File.lstat(skill_target)) end)
    assert {:ok, %File.Stat{type: :symlink}} = File.lstat(skill_target)

    conn =
      :delete
      |> conn("/api/agents/#{agent.id}/assets/skills/review")

    conn = AgentController.remove_asset(conn, %{"id" => agent.id, "kind" => "skills", "name" => "review"})
    assert conn.status == 200
    payload = Jason.decode!(conn.resp_body)
    assert payload["agent"]["skillNames"] == []

    wait_until(fn -> File.lstat(skill_target) == {:error, :enoent} end)
  end

  defp agent_attrs(suffix) do
    %{
      provider: "codex",
      name: "Codex #{suffix}",
      auth_mode: "subscription",
      codex_home: Path.join(System.tmp_dir!(), "symphony-agent-controller-#{suffix}-#{System.unique_integer([:positive])}"),
      credential_status: "configured"
    }
  end

  defp reset_json_store do
    if Store.configured_backend() == :json and Process.whereis(SymphonyElixir.Store.Json) do
      :sys.replace_state(SymphonyElixir.Store.Json, fn state ->
        %{
          state
          | registered_agents: %{},
            registered_agent_order: []
        }
      end)
    end
  end

  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)

  defp wait_until(fun, attempts \\ 20)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(25)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(_fun, 0), do: flunk("condition was not met")
end
