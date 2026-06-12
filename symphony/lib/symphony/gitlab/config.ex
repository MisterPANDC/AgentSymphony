defmodule Symphony.GitLab.Config do
  @moduledoc """
  Server-side GitLab project configuration for local single-user mode.
  """

  alias Symphony.GitLab.Error
  alias SymphonyElixir.Dotenv

  defstruct [
    :gitlab_base_url,
    :gitlab_api_root,
    :gitlab_project_ref,
    :gitlab_project_path_param,
    :token,
    :source,
    bind_host: "127.0.0.1",
    port: 4000,
    shared_secret: nil,
    sync_interval_ms: 60_000,
    sync_page_size: 100,
    sync_cursor_overlap_seconds: 120,
    workspace_root: nil,
    logs_root: "./log",
    mode: "local_single_user"
  ]

  @type t :: %__MODULE__{
          gitlab_base_url: String.t(),
          gitlab_api_root: String.t(),
          gitlab_project_ref: String.t(),
          gitlab_project_path_param: String.t(),
          token: String.t(),
          source: :project_api_url | :split_config,
          bind_host: String.t(),
          port: non_neg_integer(),
          shared_secret: String.t() | nil,
          sync_interval_ms: pos_integer(),
          sync_page_size: pos_integer(),
          sync_cursor_overlap_seconds: non_neg_integer(),
          workspace_root: String.t() | nil,
          logs_root: String.t(),
          mode: String.t()
        }

  @spec load(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def load(opts \\ []) do
    if Keyword.get(opts, :load_env_file, true), do: Dotenv.load()

    with {:ok, project_config} <- project_config_from_env(),
         {:ok, token} <- token_from_env(),
         {:ok, host} <- bind_host(),
         {:ok, shared_secret} <- shared_secret(host) do
      {:ok,
       struct!(
         __MODULE__,
         project_config
         |> Map.merge(%{
           token: token,
           bind_host: host,
           port: int_env("SYMPHONY_PORT", 4000, 0),
           shared_secret: shared_secret,
           sync_interval_ms: int_env("SYMPHONY_SYNC_INTERVAL_MS", 60_000, 1),
           sync_page_size: int_env("SYMPHONY_SYNC_PAGE_SIZE", 100, 1),
           sync_cursor_overlap_seconds: int_env("SYMPHONY_SYNC_CURSOR_OVERLAP_SECONDS", 120, 0),
           workspace_root: blank_to_nil(System.get_env("SYMPHONY_WORKSPACE_ROOT")),
           logs_root: System.get_env("SYMPHONY_LOGS_ROOT") || "./log"
         })
       )}
    end
  end

  @spec parse_project_api_url(String.t()) :: {:ok, map()} | {:error, Error.t()}
  def parse_project_api_url(url) when is_binary(url) do
    uri = URI.parse(String.trim(url))

    cond do
      uri.scheme in [nil, ""] or uri.host in [nil, ""] ->
        invalid_config("GITLAB_PROJECT_API_URL must be an absolute URL")

      not is_binary(uri.path) ->
        invalid_config("GITLAB_PROJECT_API_URL must include /api/v4/projects/:project")

      true ->
        parse_project_api_path(uri, url)
    end
  end

  def parse_project_api_url(_url), do: invalid_config("GITLAB_PROJECT_API_URL must be a string")

  @spec from_split_config(String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def from_split_config(base_url, project_ref) when is_binary(base_url) and is_binary(project_ref) do
    base_uri = URI.parse(String.trim(base_url))

    cond do
      base_uri.scheme in [nil, ""] or base_uri.host in [nil, ""] ->
        invalid_config("GITLAB_BASE_URL must be an absolute URL")

      String.trim(project_ref) == "" ->
        invalid_config("GITLAB_PROJECT_ID or GITLAB_PROJECT_PATH is required")

      true ->
        base = base_url |> String.trim() |> String.trim_trailing("/")
        api_root = base <> "/api/v4"
        path_param = project_ref_path_param(project_ref)

        {:ok,
         %{
           gitlab_base_url: base,
           gitlab_api_root: api_root,
           gitlab_project_ref: project_ref,
           gitlab_project_path_param: path_param,
           source: :split_config
         }}
    end
  end

  def from_split_config(_base_url, _project_ref), do: invalid_config("GitLab split configuration is invalid")

  @spec redacted(t() | map()) :: map()
  def redacted(%__MODULE__{} = config) do
    config
    |> Map.from_struct()
    |> Map.drop([:token])
    |> Map.put(:token_status, token_status(config.token))
  end

  def redacted(%{} = map) do
    map
    |> Map.drop([:token, "token", :gitlab_token, "gitlab_token", :GITLAB_TOKEN, "GITLAB_TOKEN"])
    |> Map.put(:token_status, "redacted")
  end

  @spec redact(String.t()) :: String.t()
  def redact(value) when is_binary(value) do
    token = System.get_env("GITLAB_TOKEN")

    if is_binary(token) and token != "" do
      String.replace(value, token, "[REDACTED]")
    else
      value
    end
  end

  defp project_config_from_env do
    case blank_to_nil(System.get_env("GITLAB_PROJECT_API_URL")) do
      nil ->
        split_project_config()

      url ->
        case parse_project_api_url(url) do
          {:ok, config} -> {:ok, config}
          {:error, _} -> split_project_config()
        end
    end
  end

  defp split_project_config do
    base_url = blank_to_nil(System.get_env("GITLAB_BASE_URL"))
    project_id = blank_to_nil(System.get_env("GITLAB_PROJECT_ID"))
    project_path = blank_to_nil(System.get_env("GITLAB_PROJECT_PATH"))

    cond do
      is_nil(base_url) ->
        invalid_config("Set GITLAB_PROJECT_API_URL or GITLAB_BASE_URL")

      is_binary(project_id) ->
        from_split_config(base_url, project_id)

      is_binary(project_path) ->
        from_split_config(base_url, project_path)

      true ->
        invalid_config("Set GITLAB_PROJECT_ID or GITLAB_PROJECT_PATH")
    end
  end

  defp parse_project_api_path(uri, original_url) do
    path = uri.path || ""
    marker = "/api/v4/projects/"

    case String.split(path, marker, parts: 2) do
      [prefix, project_ref] when project_ref != "" ->
        base_path = String.trim_trailing(prefix, "/")
        base_uri = %{uri | path: empty_path_to_nil(base_path), query: nil, fragment: nil}
        base = base_uri |> URI.to_string() |> String.trim_trailing("/")
        api_root = base <> "/api/v4"
        project_path_param = project_ref |> String.split("/", parts: 2) |> hd()

        {:ok,
         %{
           gitlab_base_url: base,
           gitlab_api_root: api_root,
           gitlab_project_ref: URI.decode(project_path_param),
           gitlab_project_path_param: project_path_param,
           source: :project_api_url
         }}

      _ ->
        invalid_config("#{original_url} must contain /api/v4/projects/:project")
    end
  end

  defp empty_path_to_nil(""), do: nil
  defp empty_path_to_nil(path), do: path

  defp project_ref_path_param(project_ref) do
    project_ref = String.trim(project_ref)

    case Integer.parse(project_ref) do
      {_, ""} -> project_ref
      _ -> URI.encode(project_ref, &URI.char_unreserved?/1)
    end
  end

  defp token_from_env do
    case blank_to_nil(System.get_env("GITLAB_TOKEN")) do
      nil -> invalid_config("Set GITLAB_TOKEN")
      token -> {:ok, token}
    end
  end

  defp bind_host do
    {:ok, blank_to_nil(System.get_env("SYMPHONY_BIND_HOST")) || "127.0.0.1"}
  end

  defp shared_secret(host) do
    secret = blank_to_nil(System.get_env("SYMPHONY_SHARED_SECRET"))

    cond do
      loopback_host?(host) ->
        {:ok, secret}

      is_binary(secret) and secret != "change-me" ->
        {:ok, secret}

      true ->
        invalid_config("SYMPHONY_SHARED_SECRET is required when SYMPHONY_BIND_HOST is not loopback")
    end
  end

  defp loopback_host?(host) when host in ["127.0.0.1", "localhost", "::1"], do: true
  defp loopback_host?(_host), do: false

  defp int_env(name, default, minimum) do
    case System.get_env(name) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int >= minimum -> int
          _ -> default
        end

      _ ->
        default
    end
  end

  defp token_status(token) when is_binary(token) and token != "", do: "configured"
  defp token_status(_token), do: "missing"

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp invalid_config(message) do
    {:error, %Error{type: :invalid_config, message: message}}
  end
end
