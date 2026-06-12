defmodule SymphonyElixirWeb.SettingsController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias Symphony.GitLab.{Client, Config}
  alias SymphonyElixir.Store

  @spec gitlab(Conn.t(), map()) :: Conn.t()
  def gitlab(conn, _params) do
    config =
      case Config.load() do
        {:ok, config} -> Config.redacted(config)
        {:error, reason} -> %{error: %{type: reason.type, message: reason.message}, token_status: "missing"}
      end

    json(conn, %{gitlab: config, project: Store.project()})
  end

  @spec test_gitlab(Conn.t(), map()) :: Conn.t()
  def test_gitlab(conn, _params) do
    with {:ok, config} <- Config.load(),
         {:ok, result} <- Client.validate(config) do
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
      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{ok: false, error: %{type: reason.type, status: reason.status, message: reason.message}})
    end
  end

  @spec workflow(Conn.t(), map()) :: Conn.t()
  def workflow(conn, _params) do
    settings = SymphonyElixir.Config.settings!()

    json(conn, %{
      workflow: %{
        statuses: ~w(triage todo in_progress blocked review done canceled),
        dispatchCandidateStatuses: ~w(todo),
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
    case Config.load() do
      {:ok, config} -> config.sync_interval_ms
      _ -> 60_000
    end
  end

  defp sync_overlap do
    case Config.load() do
      {:ok, config} -> config.sync_cursor_overlap_seconds
      _ -> 120
    end
  end
end
