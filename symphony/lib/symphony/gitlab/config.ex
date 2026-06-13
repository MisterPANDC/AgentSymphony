defmodule Symphony.GitLab.Config do
  @moduledoc """
  Server-side GitLab project configuration built from a selected repository.
  """

  alias Symphony.GitLab.Error

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
    mode: "gitlab_oidc"
  ]

  @type t :: %__MODULE__{
          gitlab_base_url: String.t(),
          gitlab_api_root: String.t(),
          gitlab_project_ref: String.t(),
          gitlab_project_path_param: String.t(),
          token: String.t() | nil,
          source: :oidc_issuer | :project_setting,
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

  @spec from_project_setting(map(), String.t() | nil) :: {:ok, t()} | {:error, Error.t()}
  def from_project_setting(project, token \\ nil)

  def from_project_setting(%{api_root: api_root, project_ref: project_ref}, token)
      when is_binary(api_root) and is_binary(project_ref) do
    base = api_root |> String.replace_suffix("/api/v4", "") |> String.trim_trailing("/")

    {:ok,
     struct!(__MODULE__, %{
       gitlab_base_url: base,
       gitlab_api_root: api_root,
       gitlab_project_ref: project_ref,
       gitlab_project_path_param: project_ref_path_param(project_ref),
       token: token,
       source: :project_setting,
       bind_host: System.get_env("SYMPHONY_BIND_HOST") || "127.0.0.1",
       port: int_env("SYMPHONY_PORT", 4000, 0),
       shared_secret: nil,
       sync_interval_ms: int_env("SYMPHONY_SYNC_INTERVAL_MS", 60_000, 1),
       sync_page_size: int_env("SYMPHONY_SYNC_PAGE_SIZE", 100, 1),
       sync_cursor_overlap_seconds: int_env("SYMPHONY_SYNC_CURSOR_OVERLAP_SECONDS", 120, 0),
       workspace_root: blank_to_nil(System.get_env("SYMPHONY_WORKSPACE_ROOT")),
       logs_root: System.get_env("SYMPHONY_LOGS_ROOT") || "./log"
     })}
  end

  def from_project_setting(_project, _token), do: invalid_config("Project setting is missing GitLab API root or project ref")

  @spec redacted(t() | map()) :: map()
  def redacted(%__MODULE__{} = config) do
    config
    |> Map.from_struct()
    |> Map.drop([:token])
    |> Map.put(:token_status, token_status(config.token))
  end

  def redacted(%{} = map) do
    map
    |> Map.drop([:token, "token", :gitlab_token, "gitlab_token"])
    |> Map.put(:token_status, "redacted")
  end

  @spec redact(String.t()) :: String.t()
  def redact(value) when is_binary(value), do: value

  defp project_ref_path_param(project_ref) do
    project_ref = String.trim(project_ref)

    case Integer.parse(project_ref) do
      {_, ""} -> project_ref
      _ -> URI.encode(project_ref, &URI.char_unreserved?/1)
    end
  end

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
