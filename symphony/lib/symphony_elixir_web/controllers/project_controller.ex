defmodule SymphonyElixirWeb.ProjectController do
  use Phoenix.Controller, formats: [:json]

  import Plug.Conn

  alias Plug.Conn
  alias Symphony.GitLab.{Client, Error}
  alias Symphony.GitLab.Config, as: GitLabConfig
  alias SymphonyElixir.Auth.{GitLabAccess, ProjectCache, TokenManager}
  alias SymphonyElixir.Auth.Config, as: AuthConfig
  alias SymphonyElixir.Store
  alias SymphonyElixir.Sync.Poller
  alias SymphonyElixirWeb.AuthPlug

  @spec index(Conn.t(), map()) :: Conn.t()
  def index(conn, params) do
    with %{} = user <- AuthPlug.current_user(conn),
         {:ok, projects} <- user_projects(conn, user, force_refresh?: force_refresh?(params)) do
      json(conn, %{projects: projects})
    else
      nil -> unauthorized(conn)
      {:error, reason} -> error(conn, 422, "project_list_failed", error_message(reason))
    end
  end

  @spec activate(Conn.t(), map()) :: Conn.t()
  def activate(conn, %{"id" => project_id}) do
    auth_config = conn.assigns[:auth_config] || %AuthConfig{}

    with %{} = user <- AuthPlug.current_user(conn),
         {:ok, access_token} <- user_access_token(user),
         {:ok, gitlab} <- gitlab_config(conn),
         {:ok, raw_project} <- project_from_cache_or_gitlab(user, gitlab, project_id, access_token),
         project <- upsert_project(gitlab, raw_project),
         {:ok, project_config} <- GitLabConfig.from_project_setting(project),
         {:ok, membership} <- GitLabAccess.project_membership(project_config, auth_config, user.gitlab_user_id, access_token),
         true <- membership.access_level >= auth_config.min_access_level || {:error, :insufficient_gitlab_access} do
      :ok = Poller.reset_issue_cursor(project.id)
      membership = Store.upsert_project_membership(user.identity_id, project.id, membership)
      updated_user = session_user(user, membership, project)

      conn
      |> put_session(:current_user, updated_user)
      |> json(%{
        project: project,
        user: public_user(updated_user),
        permissions: permissions(updated_user, auth_config)
      })
    else
      nil -> unauthorized(conn)
      {:error, :insufficient_gitlab_access} -> error(conn, 403, "insufficient_gitlab_access", "Your GitLab account does not have enough access to this project.")
      {:error, reason} -> error(conn, 422, "project_activate_failed", error_message(reason))
    end
  end

  def activate(conn, _params), do: error(conn, 400, "missing_project", "Project id is required.")

  defp user_projects(conn, user, opts) do
    with {:ok, access_token} <- user_access_token(user),
         {:ok, gitlab} <- gitlab_config(conn),
         {:ok, raw_projects} <- cached_user_projects(user, gitlab, access_token, Keyword.get(opts, :force_refresh?, false)) do
      selected_project_id = selected_project_id(conn)
      stored_by_gitlab_id = Store.projects() |> Map.new(&{to_string(&1.project_id), &1})

      projects =
        raw_projects
        |> Enum.map(fn raw ->
          stored = Map.get(stored_by_gitlab_id, to_string(raw["id"]))
          project_dto(raw, selected_project_id, stored)
        end)

      {:ok, projects}
    end
  end

  defp cached_user_projects(user, gitlab, access_token, true), do: fetch_user_projects(user, gitlab, access_token)

  defp cached_user_projects(user, gitlab, access_token, _force_refresh?) do
    key = project_cache_key(user, gitlab)

    case ProjectCache.get(key) do
      {:ok, raw_projects} -> {:ok, raw_projects}
      :miss -> fetch_user_projects(user, gitlab, access_token)
    end
  end

  defp fetch_user_projects(user, gitlab, access_token) do
    with {:ok, raw_projects} <- Client.list_user_projects(gitlab, %{}, auth: {:bearer, access_token}) do
      ProjectCache.put(project_cache_key(user, gitlab), raw_projects)
      {:ok, raw_projects}
    end
  end

  defp project_from_cache_or_gitlab(user, gitlab, project_id, access_token) do
    case ProjectCache.find_project(project_cache_key(user, gitlab), project_id) do
      {:ok, raw_project} -> {:ok, raw_project}
      :miss -> Client.get_project_by_id(gitlab, project_id, auth: {:bearer, access_token})
    end
  end

  defp project_cache_key(%{identity_id: identity_id}, %GitLabConfig{gitlab_api_root: api_root}), do: {identity_id, api_root}

  defp user_access_token(%{identity_id: identity_id}) when is_binary(identity_id), do: TokenManager.access_token(identity_id)
  defp user_access_token(_user), do: {:error, :missing_identity_id}

  defp gitlab_config(conn) do
    auth_config = conn.assigns[:auth_config] || %AuthConfig{}

    base =
      auth_config.issuer
      |> to_string()
      |> String.trim()
      |> String.trim_trailing("/")

    if base == "" do
      {:error, :missing_gitlab_issuer}
    else
      {:ok,
       %GitLabConfig{
         gitlab_base_url: base,
         gitlab_api_root: base <> "/api/v4",
         gitlab_project_ref: "0",
         gitlab_project_path_param: "0",
         token: nil,
         source: :oidc_issuer,
         sync_page_size: 100
       }}
    end
  end

  defp upsert_project(gitlab, raw) do
    Store.upsert_project(%{
      api_root: gitlab.gitlab_api_root,
      project_ref: raw["path_with_namespace"] || to_string(raw["id"]),
      project_id: raw["id"],
      path_with_namespace: raw["path_with_namespace"],
      name: raw["name"],
      web_url: raw["web_url"],
      visibility: raw["visibility"],
      last_validated_at: DateTime.utc_now(),
      last_validation_error: nil,
      read_only: false
    })
  end

  defp project_dto(project, selected_project_id, stored)

  defp project_dto(%{project_id: _} = project, selected_project_id, _stored) do
    %{
      id: project.project_id,
      name: project.name,
      path_with_namespace: project.path_with_namespace,
      web_url: project.web_url,
      visibility: project.visibility,
      last_activity_at: nil,
      selected: project.id == selected_project_id,
      project_setting_id: project.id,
      project_access_token_status: project.project_access_token_status || "missing"
    }
  end

  defp project_dto(raw, selected_project_id, stored) do
    %{
      id: raw["id"],
      name: raw["name"],
      path_with_namespace: raw["path_with_namespace"],
      web_url: raw["web_url"],
      visibility: raw["visibility"],
      last_activity_at: raw["last_activity_at"],
      selected: stored && stored.id == selected_project_id,
      project_setting_id: stored && stored.id,
      project_access_token_status: (stored && stored.project_access_token_status) || "missing"
    }
  end

  defp selected_project_id(conn) do
    case AuthPlug.current_user(conn) do
      %{project_setting_id: project_setting_id} -> project_setting_id
      _ -> nil
    end
  end

  defp force_refresh?(%{"refresh" => value}) when value in ["1", "true"], do: true
  defp force_refresh?(_params), do: false

  defp session_user(user, membership, project) do
    user
    |> Map.merge(%{
      project_membership_id: membership.id,
      project_setting_id: project.id,
      access_level: membership.access_level,
      membership_checked_at: System.system_time(:second)
    })
  end

  defp public_user(user) do
    %{
      provider: user[:provider],
      issuer: user[:issuer],
      gitlab_user_id: user[:gitlab_user_id],
      username: user[:username],
      name: user[:name],
      email: user[:email],
      avatar_url: user[:avatar_url],
      profile_url: user[:profile_url],
      access_level: user[:access_level],
      role: AuthConfig.role_for_access_level(user[:access_level]),
      project_setting_id: user[:project_setting_id]
    }
  end

  defp permissions(user, %AuthConfig{} = config) do
    access_level = Map.get(user, :access_level, 0)

    %{
      read: access_level >= config.min_access_level,
      write: access_level >= config.write_access_level,
      admin: access_level >= config.admin_access_level,
      requiredAccessLevel: config.min_access_level,
      writeAccessLevel: config.write_access_level,
      adminAccessLevel: config.admin_access_level
    }
  end

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: %{code: "authentication_required", message: "Sign in with GitLab to continue."}})
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end

  defp error_message(%Error{} = error), do: error.message
  defp error_message(reason), do: inspect(reason)
end
