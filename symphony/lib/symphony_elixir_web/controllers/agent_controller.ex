defmodule SymphonyElixirWeb.AgentController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.AgentMcpRegistry
  alias SymphonyElixir.Config
  alias SymphonyElixir.Orchestrator
  alias SymphonyElixir.Store

  @available_agents [
    %{
      provider: "codex",
      label: "Codex",
      description: "OpenAI Codex CLI agent",
      modes: ["subscription", "api", "auth_json"]
    }
  ]

  @spec index(Conn.t(), map()) :: Conn.t()
  def index(conn, _params) do
    rate_limits = runtime_rate_limits()
    mcp = mcp_registry_dto()
    registered_mcp_servers = Map.get(mcp, :mcpServers, %{})
    agents = Store.list_registered_agents() |> Enum.map(&agent_dto(&1, rate_limits, registered_mcp_servers))
    json(conn, %{agents: agents, availableAgents: @available_agents, mcp: mcp})
  end

  @spec mcp(Conn.t(), map()) :: Conn.t()
  def mcp(conn, _params) do
    json(conn, %{mcp: mcp_registry_dto()})
  end

  @spec create_mcp(Conn.t(), map()) :: Conn.t()
  def create_mcp(conn, params) do
    with {:ok, _registry} <- AgentMcpRegistry.put_server(params) do
      json(conn, %{mcp: mcp_registry_dto()})
    else
      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> json(%{ok: false, error: error_payload(reason)})
    end
  end

  @spec register(Conn.t(), map()) :: Conn.t()
  def register(conn, %{"provider" => "codex", "authMode" => auth_mode} = params)
      when auth_mode in ["subscription", "api", "auth_json"] do
    with {:ok, credential} <- credential_input(auth_mode, params),
         {:ok, mcp_server_names} <- mcp_server_names_input(params),
         {:ok, agent_name} <- agent_name_input(params),
         {:ok, attrs} <- build_codex_agent_attrs(auth_mode, mcp_server_names, agent_name),
         :ok <- File.mkdir_p(attrs.codex_home),
         :ok <- preflight_codex_environment(attrs.codex_home),
         {:ok, agent} <- Store.create_registered_agent(attrs),
         {:ok, login} <- bootstrap_codex_credentials(agent, credential) do
      conn
      |> put_status(:created)
      |> json(%{agent: agent_dto(login.agent), login: login_dto(login)})
    else
      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> json(%{ok: false, error: error_payload(reason)})
    end
  end

  def register(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{
      ok: false,
      error: %{
        type: :invalid_agent_registration,
        message: "Only Codex agents with subscription, api, or auth.json mode are supported."
      }
    })
  end

  @spec login(Conn.t(), map()) :: Conn.t()
  def login(conn, %{"id" => id} = params) do
    agent = Enum.find(Store.list_registered_agents(), &(&1.id == id))

    with %{} = agent <- agent || {:error, :agent_not_found},
         {:ok, credential} <- credential_input(agent.auth_mode, params),
         {:ok, login} <- bootstrap_codex_credentials(agent, credential) do
      json(conn, %{agent: agent_dto(login.agent), login: login_dto(login)})
    else
      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> json(%{ok: false, error: error_payload(reason)})
    end
  end

  @spec refresh_usage(Conn.t(), map()) :: Conn.t()
  def refresh_usage(conn, %{"id" => id}) do
    agent = Enum.find(Store.list_registered_agents(), &(&1.id == id))

    with %{} = agent <- agent || {:error, :agent_not_found},
         {:ok, agent} <-
           Store.update_registered_agent(
             agent.id,
             refreshed_usage_attrs(agent, runtime_rate_limits())
           ) do
      json(conn, %{agent: agent_dto(agent)})
    else
      {:error, reason} ->
        conn
        |> put_status(error_status(reason))
        |> json(%{ok: false, error: error_payload(reason)})
    end
  end

  @spec dispatch(Conn.t(), map()) :: Conn.t()
  def dispatch(conn, _params) do
    json(conn, %{dispatch: Orchestrator.request_refresh()})
  end

  defp build_codex_agent_attrs(auth_mode, mcp_server_names, agent_name) do
    id = Ecto.UUID.generate()
    home = codex_home(id)

    {:ok,
     %{
       id: id,
       provider: "codex",
       name: agent_name,
       auth_mode: auth_mode,
       codex_home: home,
       credential_status: "pending",
       mcp_server_names: mcp_server_names
     }}
  rescue
    reason -> {:error, reason}
  end

  defp codex_home(id) do
    settings = Config.settings!()
    Path.join([settings.home, "agent_homes", "codex", "codex-#{String.slice(id, 0, 8)}"])
  end

  defp preflight_codex_environment(codex_home) do
    with {:ok, executable} <- codex_executable(),
         :ok <- ensure_writable_directory(codex_home),
         {output, 0} <-
           System.cmd(executable, ["mcp", "list", "--json"], env: [{"CODEX_HOME", codex_home}]),
         {:ok, servers} <- Jason.decode(output),
         true <- is_list(servers) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      {output, status} -> {:error, {:codex_mcp_probe_failed, status, String.trim(output)}}
      _ -> {:error, :codex_mcp_probe_failed}
    end
  rescue
    error -> {:error, {:codex_preflight_failed, Exception.message(error)}}
  end

  defp codex_executable do
    case System.find_executable("codex") do
      nil -> {:error, :codex_cli_missing}
      executable -> {:ok, executable}
    end
  end

  defp ensure_writable_directory(path) do
    probe = Path.join(path, ".symphony-preflight")

    with :ok <- File.mkdir_p(path),
         :ok <- File.write(probe, "ok\n"),
         :ok <- File.rm(probe) do
      :ok
    else
      {:error, reason} -> {:error, {:codex_home_not_writable, reason}}
    end
  end

  defp bootstrap_codex_credentials(%{auth_mode: "auth_json"} = agent, auth_json) do
    path = Path.join(agent.codex_home, "auth.json")

    with :ok <- File.mkdir_p(agent.codex_home),
         :ok <- File.write(path, auth_json),
         :ok <- File.chmod(path, 0o600),
         {:ok, agent} <-
           Store.update_registered_agent(agent.id, %{
             credential_status: "configured",
             last_login_exit_status: 0,
             last_login_message: "auth.json imported"
           }),
         {:ok, agent} <- start_mcp_install(agent) do
      {:ok, %{agent: agent, command: nil, startedAt: nil}}
    else
      {:error, reason} -> {:error, {:auth_json_write_failed, reason}}
    end
  end

  defp bootstrap_codex_credentials(agent, api_key), do: start_codex_login(agent, api_key)

  defp refreshed_usage_attrs(%{auth_mode: "subscription"}, %{} = rate_limits) do
    %{
      usage_status: "available",
      usage_snapshot: rate_limits,
      usage_checked_at: now(),
      usage_error: nil
    }
  end

  defp refreshed_usage_attrs(%{auth_mode: "subscription"}, _rate_limits) do
    %{
      usage_status: "unavailable",
      usage_snapshot: nil,
      usage_checked_at: now(),
      usage_error: "Codex has not reported subscription rate limits yet."
    }
  end

  defp refreshed_usage_attrs(_agent, _rate_limits) do
    %{
      usage_status: "not_applicable",
      usage_snapshot: nil,
      usage_checked_at: now(),
      usage_error: nil
    }
  end

  defp start_codex_login(agent, api_key) do
    started_at = DateTime.utc_now() |> DateTime.truncate(:second)

    with {:ok, agent} <-
           Store.update_registered_agent(agent.id, %{
             credential_status: "login_started",
             login_started_at: started_at,
             last_login_exit_status: nil,
             last_login_message: nil
           }) do
      Task.start(fn -> run_codex_login(agent, api_key) end)

      {:ok,
       %{
         agent: agent,
         command: login_command(agent),
         startedAt: started_at
       }}
    end
  end

  defp run_codex_login(agent, api_key) do
    executable = System.find_executable("codex") || "codex"
    args = if agent.auth_mode == "api", do: ["login", "--with-api-key"], else: ["login"]
    opts = [env: [{"CODEX_HOME", agent.codex_home}], stderr_to_stdout: true]
    opts = if agent.auth_mode == "api", do: Keyword.put(opts, :input, "#{api_key}\n"), else: opts

    case System.cmd(executable, args, opts) do
      {output, 0} ->
        case Store.update_registered_agent(agent.id, %{
               credential_status: "configured",
               last_login_exit_status: 0,
               last_login_message: String.trim(output)
             }) do
          {:ok, agent} -> start_mcp_install(agent)
          {:error, _reason} -> :ok
        end

      {output, status} ->
        Store.update_registered_agent(agent.id, %{
          credential_status: "failed",
          last_login_exit_status: status,
          last_login_message: String.trim(output)
        })
    end
  rescue
    error ->
      Store.update_registered_agent(agent.id, %{
        credential_status: "failed",
        last_login_message: Exception.message(error)
      })
  end

  defp start_mcp_install(agent) do
    started_at = now()

    with {:ok, agent} <-
           Store.update_registered_agent(agent.id, %{
             mcp_install_status: "installing",
             mcp_install_started_at: started_at,
             mcp_install_finished_at: nil,
             mcp_install_exit_status: nil,
             mcp_install_message: nil
           }) do
      Task.start(fn -> run_mcp_install(agent) end)
      {:ok, agent}
    end
  end

  defp run_mcp_install(agent) do
    with {:ok, payload} <- mcp_install_payload(agent),
         {:ok, payload_json} <- Jason.encode(payload, pretty: true),
         payload_path = Path.join(System.tmp_dir!(), "symphony-mcp-#{agent.id}.json"),
         :ok <- File.write(payload_path, payload_json <> "\n"),
         :ok <- File.chmod(payload_path, 0o600),
         {:ok, script} <- mcp_install_script(),
         {output, status} <-
           System.cmd(script, [payload_path],
             env: [{"CODEX_HOME", agent.codex_home}],
             stderr_to_stdout: true
           ) do
      File.rm(payload_path)

      Store.update_registered_agent(agent.id, %{
        mcp_install_status: if(status == 0, do: "configured", else: "failed"),
        mcp_install_finished_at: now(),
        mcp_install_exit_status: status,
        mcp_install_message: String.trim(output)
      })
    else
      {:error, reason} ->
        Store.update_registered_agent(agent.id, %{
          mcp_install_status: "failed",
          mcp_install_finished_at: now(),
          mcp_install_message: inspect(reason)
        })
    end
  rescue
    error ->
      Store.update_registered_agent(agent.id, %{
        mcp_install_status: "failed",
        mcp_install_finished_at: now(),
        mcp_install_message: Exception.message(error)
      })
  end

  defp mcp_install_payload(agent) do
    with {:ok, registered_servers} <- AgentMcpRegistry.list_servers(),
         {:ok, servers} <- AgentMcpRegistry.selected_servers(Map.get(agent, :mcp_server_names) || []) do
      {:ok,
       %{
         agent_id: agent.id,
         provider: agent.provider,
         name: agent.name,
         auth_mode: agent.auth_mode,
         home: agent.codex_home,
         registeredMcpServerNames: Map.keys(registered_servers),
         mcpServers: servers
       }}
    end
  end

  defp mcp_install_script do
    priv_dir =
      case :code.priv_dir(:symphony_elixir) do
        {:error, _reason} -> Path.expand("priv", File.cwd!())
        path -> to_string(path)
      end

    script = Path.join([priv_dir, "agent_mcp", "install.sh"])

    if File.exists?(script),
      do: {:ok, script},
      else: {:error, {:mcp_install_script_missing, script}}
  end

  defp credential_input("api", %{"apiKey" => api_key}) when is_binary(api_key) do
    case String.trim(api_key) do
      "" -> {:error, :api_key_required}
      api_key -> {:ok, api_key}
    end
  end

  defp credential_input("api", _params), do: {:error, :api_key_required}

  defp credential_input("auth_json", %{"authJson" => auth_json}),
    do: normalize_auth_json(auth_json)

  defp credential_input("auth_json", _params), do: {:error, :auth_json_required}
  defp credential_input(_auth_mode, _params), do: {:ok, nil}

  defp agent_name_input(%{"name" => name}) when is_binary(name) do
    name = String.trim(name)

    cond do
      name == "" -> {:ok, "Codex"}
      String.length(name) > 80 -> {:error, :agent_name_too_long}
      true -> {:ok, name}
    end
  end

  defp agent_name_input(_params), do: {:ok, "Codex"}

  defp mcp_server_names_input(%{"mcpServerNames" => names}) when is_list(names) do
    names =
      names
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()

    case AgentMcpRegistry.selected_servers(names) do
      {:ok, _servers} -> {:ok, names}
      {:error, reason} -> {:error, reason}
    end
  end

  defp mcp_server_names_input(_params), do: {:ok, []}

  defp normalize_auth_json(auth_json) when is_binary(auth_json) do
    with {:ok, decoded} <- Jason.decode(auth_json),
         {:ok, encoded} <- Jason.encode(decoded, pretty: true) do
      {:ok, encoded <> "\n"}
    else
      _ -> {:error, :invalid_auth_json}
    end
  end

  defp normalize_auth_json(auth_json) when is_map(auth_json) do
    case Jason.encode(auth_json, pretty: true) do
      {:ok, encoded} -> {:ok, encoded <> "\n"}
      _ -> {:error, :invalid_auth_json}
    end
  end

  defp normalize_auth_json(_auth_json), do: {:error, :invalid_auth_json}

  defp agent_dto(agent, runtime_rate_limits \\ nil, registered_mcp_servers \\ %{}) do
    %{
      id: agent.id,
      provider: agent.provider,
      name: agent.name,
      authMode: agent.auth_mode,
      codexHome: agent.codex_home,
      credentialStatus: agent.credential_status,
      loginStartedAt: iso(agent.login_started_at),
      lastLoginExitStatus: agent.last_login_exit_status,
      lastLoginMessage: agent.last_login_message,
      mcpInstallStatus: Map.get(agent, :mcp_install_status) || "pending",
      mcpInstallStartedAt: iso(Map.get(agent, :mcp_install_started_at)),
      mcpInstallFinishedAt: iso(Map.get(agent, :mcp_install_finished_at)),
      mcpInstallExitStatus: Map.get(agent, :mcp_install_exit_status),
      mcpInstallMessage: Map.get(agent, :mcp_install_message),
      mcpServerNames: Map.get(agent, :mcp_server_names) || [],
      mcpInstalledServers: installed_mcp_servers(agent, registered_mcp_servers),
      usage: usage_dto(agent, runtime_rate_limits),
      insertedAt: iso(agent.inserted_at),
      updatedAt: iso(agent.updated_at)
    }
  end

  defp installed_mcp_servers(agent, registered_mcp_servers) do
    selected = MapSet.new(Map.get(agent, :mcp_server_names) || [])

    case codex_mcp_list(agent) do
      {:ok, servers} ->
        servers
        |> Enum.map(fn server ->
          name = Map.get(server, "name")

          %{
            name: name,
            enabled: Map.get(server, "enabled", true),
            selected: MapSet.member?(selected, name),
            registered: is_binary(name) and Map.has_key?(registered_mcp_servers, name)
          }
        end)
        |> Enum.filter(&is_binary(&1.name))

      {:error, _reason} ->
        []
    end
  end

  defp codex_mcp_list(agent) do
    executable = System.find_executable("codex") || "codex"

    case System.cmd(executable, ["mcp", "list", "--json"], env: [{"CODEX_HOME", agent.codex_home}]) do
      {output, 0} -> Jason.decode(output)
      {output, status} -> {:error, {:codex_mcp_list_failed, status, String.trim(output)}}
    end
  rescue
    error -> {:error, error}
  end

  defp usage_dto(%{auth_mode: "subscription"} = agent, runtime_rate_limits) do
    snapshot = Map.get(agent, :usage_snapshot) || runtime_rate_limits

    status =
      if is_map(snapshot), do: "available", else: Map.get(agent, :usage_status) || "unknown"

    source =
      cond do
        is_map(Map.get(agent, :usage_snapshot)) -> "agent"
        is_map(runtime_rate_limits) -> "runtime"
        true -> nil
      end

    %{
      status: status,
      rateLimits: snapshot,
      checkedAt: iso(Map.get(agent, :usage_checked_at)),
      error: Map.get(agent, :usage_error),
      source: source
    }
  end

  defp usage_dto(agent, _runtime_rate_limits) do
    %{
      status: Map.get(agent, :usage_status) || "not_applicable",
      rateLimits: nil,
      checkedAt: iso(Map.get(agent, :usage_checked_at)),
      error: Map.get(agent, :usage_error),
      source: nil
    }
  end

  defp login_dto(login) do
    %{
      command: login.command,
      startedAt: iso(login.startedAt)
    }
  end

  defp login_command(agent) do
    home = String.replace(agent.codex_home, "\"", "\\\"")

    if agent.auth_mode == "api" do
      ~s(CODEX_HOME="#{home}" codex login --with-api-key)
    else
      ~s(CODEX_HOME="#{home}" codex login)
    end
  end

  defp error_status(:api_key_required), do: 400
  defp error_status(:auth_json_required), do: 400
  defp error_status(:invalid_auth_json), do: 400
  defp error_status(:invalid_mcp_server_name), do: 400
  defp error_status(:invalid_mcp_server_command), do: 400
  defp error_status(:invalid_mcp_server_args), do: 400
  defp error_status(:invalid_mcp_server_env), do: 400
  defp error_status(:invalid_mcp_server_startup_timeout), do: 400
  defp error_status(:agent_name_too_long), do: 400
  defp error_status(:codex_cli_missing), do: 400
  defp error_status({:codex_home_not_writable, _reason}), do: 400
  defp error_status({:codex_mcp_probe_failed, _status, _output}), do: 400
  defp error_status(:codex_mcp_probe_failed), do: 400
  defp error_status({:codex_preflight_failed, _message}), do: 400
  defp error_status({:unknown_mcp_server, _name}), do: 400
  defp error_status(:agent_not_found), do: 404
  defp error_status(_reason), do: 422

  defp error_payload(:api_key_required),
    do: %{type: :api_key_required, message: "API key is required for API mode."}

  defp error_payload(:auth_json_required),
    do: %{type: :auth_json_required, message: "auth.json is required for auth.json mode."}

  defp error_payload(:invalid_auth_json),
    do: %{type: :invalid_auth_json, message: "auth.json must be valid JSON."}

  defp error_payload(:agent_not_found),
    do: %{type: :agent_not_found, message: "Agent registration was not found."}

  defp error_payload(:invalid_mcp_server_name),
    do: %{type: :invalid_mcp_server_name, message: "MCP server name must use letters, numbers, dots, dashes, or underscores."}

  defp error_payload(:invalid_mcp_server_command),
    do: %{type: :invalid_mcp_server_command, message: "MCP server command is required."}

  defp error_payload(:invalid_mcp_server_args),
    do: %{type: :invalid_mcp_server_args, message: "MCP server args must be a string list."}

  defp error_payload(:invalid_mcp_server_env),
    do: %{type: :invalid_mcp_server_env, message: "MCP server env must be a string map."}

  defp error_payload(:invalid_mcp_server_startup_timeout),
    do: %{type: :invalid_mcp_server_startup_timeout, message: "MCP startup timeout must be a positive integer."}

  defp error_payload(:agent_name_too_long),
    do: %{type: :agent_name_too_long, message: "Agent name must be 80 characters or fewer."}

  defp error_payload(:codex_cli_missing),
    do: %{type: :codex_cli_missing, message: "Codex CLI was not found in PATH."}

  defp error_payload({:codex_home_not_writable, reason}),
    do: %{type: :codex_home_not_writable, message: "CODEX_HOME is not writable: #{inspect(reason)}"}

  defp error_payload({:codex_mcp_probe_failed, status, output}),
    do: %{type: :codex_mcp_probe_failed, message: "Codex MCP check failed with exit #{status}: #{output}"}

  defp error_payload(:codex_mcp_probe_failed),
    do: %{type: :codex_mcp_probe_failed, message: "Codex MCP check did not return a valid server list."}

  defp error_payload({:codex_preflight_failed, message}),
    do: %{type: :codex_preflight_failed, message: message}

  defp error_payload({:unknown_mcp_server, name}),
    do: %{type: :unknown_mcp_server, message: "Unknown MCP server: #{name}"}

  defp error_payload(%Ecto.Changeset{}),
    do: %{type: :invalid_agent, message: "Agent registration could not be saved."}

  defp error_payload({:auth_json_write_failed, reason}),
    do: %{type: :auth_json_write_failed, message: inspect(reason)}

  defp error_payload(reason), do: %{type: :agent_registration_failed, message: inspect(reason)}

  defp mcp_registry_dto do
    case AgentMcpRegistry.dto() do
      {:ok, dto} -> dto
      {:error, reason} -> %{path: AgentMcpRegistry.path(), mcpServers: %{}, error: inspect(reason)}
    end
  end

  defp runtime_rate_limits do
    case Orchestrator.snapshot(Orchestrator, 500) do
      %{rate_limits: %{} = rate_limits} -> rate_limits
      _ -> nil
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp iso(%DateTime{} = datetime),
    do: datetime |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp iso(nil), do: nil
  defp iso(value) when is_binary(value), do: value
end
