defmodule SymphonyElixirWeb.ObservabilityApiController do
  @moduledoc """
  JSON API for Symphony observability data.
  """

  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.Monitor.DTO
  alias SymphonyElixir.Sync.Poller
  alias SymphonyElixirWeb.AuthPlug

  @spec state(Conn.t(), map()) :: Conn.t()
  def state(conn, _params) do
    json(conn, DTO.v1_state(snapshot_timeout_ms(), monitor_filters(conn)))
  end

  @spec issue(Conn.t(), map()) :: Conn.t()
  def issue(conn, %{"issue_identifier" => issue_identifier}) do
    case DTO.issue_debug(issue_identifier, snapshot_timeout_ms()) do
      {:ok, payload} ->
        if visible_issue?(conn, payload.issue) do
          json(conn, payload)
        else
          error_response(conn, 404, "issue_not_found", "Issue not found")
        end

      {:error, :issue_not_found} ->
        error_response(conn, 404, "issue_not_found", "Issue not found")
    end
  end

  defp visible_issue?(conn, issue) do
    case current_project_setting_id(conn) do
      nil -> false
      project_id -> issue[:gitlab_project_setting_id] == project_id
    end
  end

  defp current_project_setting_id(conn) do
    case AuthPlug.current_user(conn) do
      %{project_setting_id: project_setting_id} -> project_setting_id
      _ -> nil
    end
  end

  @spec refresh(Conn.t(), map()) :: Conn.t()
  def refresh(conn, _params) do
    Poller.refresh()

    conn
    |> put_status(202)
    |> json(DTO.v1_state(snapshot_timeout_ms(), monitor_filters(conn)))
  end

  @spec method_not_allowed(Conn.t(), map()) :: Conn.t()
  def method_not_allowed(conn, _params) do
    error_response(conn, 405, "method_not_allowed", "Method not allowed")
  end

  @spec not_found(Conn.t(), map()) :: Conn.t()
  def not_found(conn, _params) do
    error_response(conn, 404, "not_found", "Route not found")
  end

  defp error_response(conn, status, code, message) do
    conn
    |> put_status(status)
    |> json(%{error: %{code: code, message: message}})
  end

  defp snapshot_timeout_ms do
    SymphonyElixirWeb.Endpoint.config(:snapshot_timeout_ms) || 15_000
  end

  defp monitor_filters(conn) do
    case current_project_setting_id(conn) do
      nil -> [project_setting_id: "__no_project__", project: nil]
      project_id -> [project_setting_id: project_id, project: AuthPlug.current_project(conn)]
    end
  end
end
