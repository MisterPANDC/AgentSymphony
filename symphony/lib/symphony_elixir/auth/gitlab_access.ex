defmodule SymphonyElixir.Auth.GitLabAccess do
  @moduledoc """
  Reads effective GitLab project membership for an authenticated user.
  """

  alias Symphony.GitLab.Config, as: GitLabConfig
  alias SymphonyElixir.Auth.Config

  @timeout_ms 30_000

  @spec project_membership(GitLabConfig.t(), Config.t(), String.t() | integer(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def project_membership(%GitLabConfig{} = gitlab, %Config{} = _auth, user_id, access_token) do
    request_membership(gitlab, user_id, headers: [{"authorization", "Bearer #{access_token}"}])
  end

  @spec project_membership_with_private_token(GitLabConfig.t(), String.t() | integer()) ::
          {:ok, map()} | {:error, term()}
  def project_membership_with_private_token(%GitLabConfig{} = gitlab, user_id) do
    request_membership(gitlab, user_id, headers: [{"PRIVATE-TOKEN", gitlab.token}])
  end

  defp request_membership(%GitLabConfig{} = gitlab, user_id, auth_opts) do
    path = gitlab.gitlab_api_root <> "/projects/#{gitlab.gitlab_project_path_param}/members/all/#{user_id}"

    req_opts =
      [
        method: :get,
        url: path,
        receive_timeout: @timeout_ms
      ]
      |> Keyword.merge(auth_opts)
      |> Keyword.merge(req_extra_options())

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, normalize_membership(body)}

      {:ok, %Req.Response{status: 404}} ->
        {:error, :project_access_not_found}

      {:ok, %Req.Response{status: 401}} ->
        {:error, :gitlab_token_unauthorized}

      {:ok, %Req.Response{status: 403}} ->
        {:error, :gitlab_token_forbidden}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:gitlab_membership_http_error, status, body}}

      {:error, reason} ->
        {:error, {:gitlab_membership_request_failed, reason}}
    end
  end

  defp normalize_membership(body) when is_map(body) do
    %{
      gitlab_user_id: body["id"],
      username: body["username"],
      name: body["name"],
      avatar_url: body["avatar_url"],
      web_url: body["web_url"],
      access_level: body["access_level"],
      expires_at: body["expires_at"],
      state: body["state"],
      raw_gitlab: body
    }
  end

  defp req_extra_options do
    Application.get_env(:symphony_elixir, :gitlab_req_options, [])
  end
end
