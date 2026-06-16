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

  defp normalize_local_repo_path("", _project), do: {:ok, nil}

  defp normalize_local_repo_path(path, project) do
    case LocalRepo.validate_project_path(path, project) do
      {:ok, %{path: normalized_path}} -> {:ok, normalized_path}
      {:error, reason} -> {:error, reason}
    end
  end

  defp local_repo_status(:empty_local_repo_path), do: 400
  defp local_repo_status(:invalid_local_repo_path), do: 400
  defp local_repo_status(:local_repo_path_not_found), do: 422
  defp local_repo_status(:not_a_git_repository), do: 422
  defp local_repo_status(:local_repo_remote_missing), do: 422
  defp local_repo_status(:local_repo_project_mismatch), do: 422
  defp local_repo_status(:git_unavailable), do: 422
  defp local_repo_status(_reason), do: 422

  defp local_repo_error(:empty_local_repo_path),
    do: %{type: :empty_local_repo_path, message: "Enter a local repository path, or clear the field to leave it unset."}

  defp local_repo_error(:invalid_local_repo_path),
    do: %{type: :invalid_local_repo_path, message: "The local repository path is not valid."}

  defp local_repo_error(:local_repo_path_not_found),
    do: %{type: :local_repo_path_not_found, message: "That folder does not exist on this machine."}

  defp local_repo_error(:not_a_git_repository),
    do: %{type: :not_a_git_repository, message: "Choose a folder that is already a Git repository."}

  defp local_repo_error(:local_repo_remote_missing),
    do: %{type: :local_repo_remote_missing, message: "That repository has no origin remote to match against this GitLab project."}

  defp local_repo_error(:local_repo_project_mismatch),
    do: %{type: :local_repo_project_mismatch, message: "That repository's origin does not match the selected GitLab project."}

  defp local_repo_error(:git_unavailable),
    do: %{type: :git_unavailable, message: "Git is not available to validate that folder."}

  defp local_repo_error(reason), do: %{type: reason, message: inspect(reason)}

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
