defmodule SymphonyElixirWeb.SettingsController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias Symphony.GitLab.{Client, Error}
  alias Symphony.GitLab.Config, as: GitLabConfig
  alias SymphonyElixir.Persistence.WorkflowState
  alias SymphonyElixir.Store
  alias SymphonyElixir.Sync.Poller
  alias SymphonyElixirWeb.AuthPlug

  @spec gitlab(Conn.t(), map()) :: Conn.t()
  def gitlab(conn, _params) do
    project = AuthPlug.current_project(conn)

    config =
      case project && GitLabConfig.from_project_setting(project) do
        {:ok, config} -> GitLabConfig.redacted(config)
        _ -> %{token_status: (project && project.project_access_token_status) || "missing"}
      end

    json(conn, %{gitlab: config, project: project})
  end

  @spec test_gitlab(Conn.t(), map()) :: Conn.t()
  def test_gitlab(conn, _params) do
    with %{} = project <- AuthPlug.current_project(conn),
         {:ok, token} <- Store.project_access_token(project.id),
         {:ok, config} <- GitLabConfig.from_project_setting(project, token),
         {:ok, result} <- Client.validate(config, auth: {:private_token, token}) do
      project = result.project

      json(conn, %{
        ok: true,
        project: %{
          id: project["id"],
          name: project["name"],
          webUrl: project["web_url"],
          defaultBranch: project["default_branch"],
          pathWithNamespace: project["path_with_namespace"]
        },
        tokenPermissionMode: result.token_permission_mode,
        issueApiReachable: result.issue_api_reachable
      })
    else
      nil ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: %{type: :missing_project, message: "Select a GitLab project before testing settings."}})

      {:error, :project_access_token_missing} ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: %{type: :project_access_token_missing, message: "Set a Project Access Token before testing GitLab sync."}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: error_payload(reason)})
    end
  end

  @spec update_project_token(Conn.t(), map()) :: Conn.t()
  def update_project_token(conn, %{"projectAccessToken" => token}) when is_binary(token) do
    token = String.trim(token)

    with true <- token != "" || {:error, :empty_project_access_token},
         %{} = project <- AuthPlug.current_project(conn),
         {:ok, config} <- GitLabConfig.from_project_setting(project, token),
         {:ok, _result} <- Client.validate(config, auth: {:private_token, token}),
         {:ok, project} <- Store.put_project_access_token(project.id, token, current_identity_id(conn)),
         :ok <- Poller.reset_issue_cursor() do
      json(conn, %{ok: true, project: project})
    else
      nil ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: %{type: :missing_project, message: "Select a GitLab project before saving a Project Access Token."}})

      {:error, :empty_project_access_token} ->
        conn
        |> put_status(400)
        |> json(%{ok: false, error: %{type: :empty_project_access_token, message: "Project Access Token is required."}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: error_payload(reason)})
    end
  end

  def update_project_token(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{ok: false, error: %{type: :missing_project_access_token, message: "projectAccessToken is required."}})
  end

  @spec workflow(Conn.t(), map()) :: Conn.t()
  def workflow(conn, _params) do
    settings = SymphonyElixir.Config.settings!()

    json(conn, %{
      workflow: %{
        statuses: WorkflowState.statuses(),
        dispatchCandidateStatuses: ~w(todo in_progress merging rework),
        requiredGitlabLabels: settings.tracker.required_labels,
        maxConcurrentAgents: settings.agent.max_concurrent_agents,
        syncIntervalMs: sync_interval(),
        cursorOverlapSeconds: sync_overlap(),
        readOnlyImpacts: "GitLab writes are disabled when token permissions are read-only; internal workflow changes remain local."
      }
    })
  end

  @spec update_workflow(Conn.t(), map()) :: Conn.t()
  def update_workflow(conn, _params) do
    conn
    |> put_status(202)
    |> json(%{ok: true, message: "Workflow settings are repository-owned in WORKFLOW.md for this migration."})
  end

  defp sync_interval do
    int_env("SYMPHONY_SYNC_INTERVAL_MS", 60_000, 1)
  end

  defp sync_overlap do
    int_env("SYMPHONY_SYNC_CURSOR_OVERLAP_SECONDS", 120, 0)
  end

  defp current_identity_id(conn) do
    case AuthPlug.current_user(conn) do
      %{identity_id: identity_id} -> identity_id
      _ -> nil
    end
  end

  defp error_payload(%Error{} = reason), do: %{type: reason.type, status: reason.status, message: reason.message}
  defp error_payload(reason), do: %{type: reason, message: inspect(reason)}

  defp int_env(name, default, min) do
    case System.get_env(name) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int >= min -> int
          _ -> default
        end

      _ ->
        default
    end
  end
end
