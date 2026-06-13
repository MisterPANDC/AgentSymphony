defmodule SymphonyElixirWeb.AuthPlug do
  @moduledoc """
  Session-backed authentication and GitLab access gates for JSON APIs.
  """

  import Plug.Conn

  alias Symphony.GitLab.Config, as: GitLabConfig
  alias SymphonyElixir.Auth.{Config, GitLabAccess, TokenManager}
  alias SymphonyElixir.Store

  @membership_ttl_seconds 300

  def init(opts), do: opts

  def call(conn, :load_current_user) do
    case Config.load() do
      {:ok, %Config{} = config} ->
        conn
        |> assign(:auth_config, config)
        |> load_user(config)

      {:error, reason} ->
        conn
        |> assign(:auth_config_error, reason)
        |> assign(:current_user, nil)
    end
  end

  def call(conn, {:require_access, level}) do
    config = conn.assigns[:auth_config] || %Config{}
    user = conn.assigns[:current_user]
    required = required_access_level(config, level)

    cond do
      is_nil(user) ->
        unauthorized(conn)

      Map.get(user, :access_level, 0) < required ->
        forbidden(conn, required)

      true ->
        conn
    end
  end

  @spec actor(Plug.Conn.t()) :: String.t()
  def actor(conn) do
    case conn.assigns[:current_user] do
      %{gitlab_user_id: user_id, username: username} ->
        "gitlab:#{user_id}:#{username}"

      _ ->
        "unknown"
    end
  end

  @spec current_user(Plug.Conn.t()) :: map() | nil
  def current_user(conn), do: conn.assigns[:current_user]

  @spec current_project(Plug.Conn.t()) :: map() | nil
  def current_project(conn) do
    case current_user(conn) do
      %{project_setting_id: project_setting_id} when is_binary(project_setting_id) -> Store.project_by_id(project_setting_id)
      _ -> nil
    end
  end

  @spec oauth_access_token(Plug.Conn.t()) :: {:ok, String.t()} | {:error, term()}
  def oauth_access_token(conn) do
    with %{identity_id: identity_id} <- current_user(conn) do
      TokenManager.access_token(identity_id)
    else
      _ -> {:error, :missing_identity_id}
    end
  end

  defp load_user(conn, %Config{} = config) do
    conn
    |> get_session(:current_user)
    |> case do
      nil -> assign(conn, :current_user, nil)
      user -> refresh_membership_if_stale(conn, config, normalize_session_user(user))
    end
  end

  defp refresh_membership_if_stale(conn, config, user) do
    if is_nil(user[:project_setting_id]) or fresh_membership?(user) do
      assign(conn, :current_user, user)
    else
      do_refresh_membership(conn, config, user)
    end
  end

  defp do_refresh_membership(conn, config, user) do
    with project_setting_id when is_binary(project_setting_id) <- user[:project_setting_id],
         %{} = project <- Store.project_by_id(project_setting_id),
         {:ok, access_token} <- TokenManager.access_token(user.identity_id),
         {:ok, gitlab} <- GitLabConfig.from_project_setting(project),
         {:ok, membership} <- GitLabAccess.project_membership(gitlab, config, user.gitlab_user_id, access_token),
         true <- membership.access_level >= config.min_access_level,
         true <- is_map(project) do
      if user[:identity_id] && project[:id] do
        Store.upsert_project_membership(user.identity_id, project.id, membership)
      end

      updated =
        user
        |> Map.merge(%{
          access_level: membership.access_level,
          role: Config.role_for_access_level(membership.access_level),
          membership_checked_at: System.system_time(:second)
        })

      conn
      |> put_session(:current_user, updated)
      |> assign(:current_user, updated)
    else
      _ ->
        conn
        |> delete_session(:current_user)
        |> assign(:current_user, nil)
    end
  end

  defp fresh_membership?(%{membership_checked_at: checked_at}) when is_integer(checked_at) do
    System.system_time(:second) - checked_at < @membership_ttl_seconds
  end

  defp fresh_membership?(_user), do: false

  defp normalize_session_user(user) when is_map(user) do
    user
    |> Enum.map(fn {key, value} -> {normalize_key(key), value} end)
    |> Map.new()
  end

  defp normalize_key(key) when is_binary(key), do: String.to_atom(key)
  defp normalize_key(key), do: key

  defp required_access_level(%Config{} = config, :read), do: config.min_access_level
  defp required_access_level(%Config{} = config, :write), do: config.write_access_level
  defp required_access_level(%Config{} = config, :admin), do: config.admin_access_level
  defp required_access_level(%Config{} = config, _level), do: config.min_access_level

  defp unauthorized(conn) do
    conn
    |> put_status(:unauthorized)
    |> Phoenix.Controller.json(%{
      error: %{code: "authentication_required", message: "Sign in with GitLab to continue."},
      loginUrl: "/auth/gitlab"
    })
    |> halt()
  end

  defp forbidden(conn, required) do
    conn
    |> put_status(:forbidden)
    |> Phoenix.Controller.json(%{
      error: %{
        code: "insufficient_gitlab_access",
        message: "Your GitLab project access level is below the required level.",
        requiredAccessLevel: required
      }
    })
    |> halt()
  end
end
