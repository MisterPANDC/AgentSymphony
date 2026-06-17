defmodule SymphonyElixirWeb.SettingsController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias Symphony.GitLab.{Client, Error}
  alias Symphony.GitLab.Config, as: GitLabConfig
  alias SymphonyElixir.LocalRepo
  alias SymphonyElixir.Store
  alias SymphonyElixir.Sync.Poller
  alias SymphonyElixir.Workflow.Transitions
  alias SymphonyElixirWeb.AuthPlug

  @credential_modes ~w(project_access_token service_account)

  @spec gitlab(Conn.t(), map()) :: Conn.t()
  def gitlab(conn, _params) do
    project = AuthPlug.current_project(conn)

    config =
      case project && GitLabConfig.from_project_setting(project) do
        {:ok, config} -> GitLabConfig.redacted(config)
        _ -> %{token_status: (project && project.project_access_token_status) || "missing"}
      end

    service_account = project && Store.service_account_credential(project.api_root)

    json(conn, %{gitlab: config, project: project, serviceAccount: service_account})
  end

  @spec test_gitlab(Conn.t(), map()) :: Conn.t()
  def test_gitlab(conn, _params) do
    with %{} = project <- AuthPlug.current_project(conn),
         {:ok, credential} <- Store.automation_credential(project.id),
         {:ok, config} <- GitLabConfig.from_project_setting(project, credential.token),
         {:ok, result} <- Client.validate(config, auth: {:private_token, credential.token}) do
      project = result.project

      json(conn, %{
        ok: true,
        credentialMode: credential.mode,
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
        |> json(%{ok: false, error: %{type: :project_access_token_missing, message: "Set a Project Access Token or switch to a configured Service Account before testing GitLab sync."}})

      {:error, :service_account_token_missing} ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: %{type: :service_account_token_missing, message: "Set the global Service Account token before testing this repository in Service Account mode."}})

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
         {:ok, _project} <- Store.put_project_access_token(project.id, token, current_identity_id(conn)),
         {:ok, project} <- Store.put_project_automation_credential_mode(project.id, "project_access_token"),
         :ok <- Poller.reset_issue_cursor(project.id) do
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

  @spec update_service_account_token(Conn.t(), map()) :: Conn.t()
  def update_service_account_token(conn, %{"serviceAccountToken" => token}) when is_binary(token) do
    token = String.trim(token)
    current_project = AuthPlug.current_project(conn)

    with true <- token != "" || {:error, :empty_service_account_token},
         %{} = project <- current_project,
         {:ok, config} <- GitLabConfig.from_project_setting(project, token),
         {:ok, _result} <- Client.validate(config, auth: {:private_token, token}),
         {:ok, user} <- Client.get_current_user(config, auth: {:private_token, token}),
         {:ok, service_account} <- Store.put_service_account_token(project.api_root, token, current_identity_id(conn), service_account_attrs(user)),
         {:ok, project} <- Store.put_project_automation_credential_mode(project.id, "service_account"),
         :ok <- Poller.reset_issue_cursor(project.id) do
      json(conn, %{ok: true, project: project, serviceAccount: service_account})
    else
      nil ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: %{type: :missing_project, message: "Select a GitLab project before saving a Service Account token."}})

      {:error, :empty_service_account_token} ->
        conn
        |> put_status(400)
        |> json(%{ok: false, error: %{type: :empty_service_account_token, message: "Service Account token is required."}})

      {:error, %Error{type: type, status: status}} when type in [:not_found, :forbidden] ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: service_account_project_access_payload(current_project, status)})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: error_payload(reason)})
    end
  end

  def update_service_account_token(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{ok: false, error: %{type: :missing_service_account_token, message: "serviceAccountToken is required."}})
  end

  @spec update_credential_mode(Conn.t(), map()) :: Conn.t()
  def update_credential_mode(conn, %{"mode" => mode}) when mode in @credential_modes do
    with %{} = project <- AuthPlug.current_project(conn),
         {:ok, project} <- Store.put_project_automation_credential_mode(project.id, mode),
         :ok <- Poller.reset_issue_cursor(project.id) do
      json(conn, %{ok: true, project: project, serviceAccount: Store.service_account_credential(project.api_root)})
    else
      nil ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: %{type: :missing_project, message: "Select a GitLab project before switching credential mode."}})

      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: error_payload(reason)})
    end
  end

  def update_credential_mode(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{ok: false, error: %{type: :invalid_automation_credential_mode, message: "mode must be project_access_token or service_account."}})
  end

  @spec local_repo_candidates(Conn.t(), map()) :: Conn.t()
  def local_repo_candidates(conn, params) do
    with %{} = project <- AuthPlug.current_project(conn) do
      json(conn, %{candidates: LocalRepo.candidates(project, scope: params["scope"])})
    else
      nil ->
        conn
        |> put_status(422)
        |> json(%{
          ok: false,
          error: %{type: :missing_project, message: "Select a GitLab project before scanning local repositories."}
        })
    end
  end

  @spec update_local_repo(Conn.t(), map()) :: Conn.t()
  def update_local_repo(conn, %{"localRepoPath" => path}) when is_binary(path) do
    path = String.trim(path)

    with %{} = project <- AuthPlug.current_project(conn),
         {:ok, normalized_path} <- normalize_local_repo_path(path, project),
         {:ok, project} <- Store.put_project_local_repo_path(project.id, normalized_path) do
      json(conn, %{ok: true, project: project})
    else
      nil ->
        conn
        |> put_status(422)
        |> json(%{
          ok: false,
          error: %{type: :missing_project, message: "Select a GitLab project before saving a local repository path."}
        })

      {:error, reason} ->
        conn
        |> put_status(local_repo_status(reason))
        |> json(%{ok: false, error: local_repo_error(reason)})
    end
  end

  def update_local_repo(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{ok: false, error: %{type: :missing_local_repo_path, message: "localRepoPath is required."}})
  end

  @spec workflow(Conn.t(), map()) :: Conn.t()
  def workflow(conn, _params) do
    settings = SymphonyElixir.Config.settings!()

    json(conn, %{
      workflow: %{
        statuses: Transitions.statuses(),
        dispatchCandidateStatuses: Transitions.dispatch_candidate_statuses(),
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

  defp service_account_attrs(user) when is_map(user) do
    %{
      gitlab_user_id: user["id"] || user[:id],
      username: user["username"] || user[:username],
      name: user["name"] || user[:name],
      web_url: user["web_url"] || user["webUrl"] || user[:web_url] || user[:webUrl],
      scopes: []
    }
  end

  defp service_account_project_access_payload(project, status) do
    %{
      type: :service_account_project_access_denied,
      status: status,
      message:
        "This Service Account token cannot see #{project_label(project)}. GitLab may return 404 for private projects the token cannot access. Add the Service Account user to the project or its group, then save the token again."
    }
  end

  defp project_label(project) when is_map(project) do
    project[:path_with_namespace] || project["path_with_namespace"] || project[:project_ref] || project["project_ref"] ||
      "the selected GitLab project"
  end

  defp project_label(_project), do: "the selected GitLab project"

  defp normalize_local_repo_path("", _project), do: {:ok, nil}

  defp normalize_local_repo_path(path, project) do
    case LocalRepo.validate_project_path(path, project) do
      {:ok, repo} -> {:ok, repo.path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp local_repo_status(reason)
       when reason in [
              :empty_local_repo_path,
              :invalid_local_repo_path,
              :local_repo_path_not_found,
              :not_a_git_repository,
              :local_repo_remote_missing,
              :local_repo_project_mismatch,
              :git_unavailable
            ],
       do: 422

  defp local_repo_status(_reason), do: 500

  defp local_repo_error(reason) do
    %{
      type: reason,
      message:
        case reason do
          :empty_local_repo_path -> "Local repository path is required."
          :invalid_local_repo_path -> "Local repository path is invalid."
          :local_repo_path_not_found -> "Local repository path was not found."
          :not_a_git_repository -> "Local repository path is not a Git repository."
          :local_repo_remote_missing -> "Local repository must have an origin remote."
          :local_repo_project_mismatch -> "Local repository origin does not match the selected GitLab project."
          :git_unavailable -> "Git is not available on this machine."
          _ -> inspect(reason)
        end
    }
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
