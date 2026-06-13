defmodule SymphonyElixirWeb.AgentController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.{Orchestrator, Store}
  alias SymphonyElixirWeb.AuthPlug
  alias SymphonyElixirWeb.DTO

  @spec dispatch(Conn.t(), map()) :: Conn.t()
  def dispatch(conn, _params) do
    json(conn, %{dispatch: Orchestrator.request_refresh()})
  end

  @spec run_issue(Conn.t(), map()) :: Conn.t()
  def run_issue(conn, %{"id" => id}) do
    case find_issue(conn, id) do
      nil ->
        error(conn, 404, "issue_not_found", "Issue not found")

      issue ->
        {:ok, run} = Store.create_run(issue.id, %{status: "queued", mode: "manual"})
        Store.add_run_event(run.id, "queued", "Manual run queued from API", %{actor: AuthPlug.actor(conn)})
        Orchestrator.request_refresh()
        json(conn, %{run: DTO.run(Store.get_run(run.id))})
    end
  end

  defp find_issue(conn, id) do
    case current_project_setting_id(conn) do
      nil ->
        Store.get_issue(id) || Store.get_issue_by_iid(id) || Store.get_issue_by_identifier(id)

      project_id ->
        Store.list_issues(project_setting_id: project_id)
        |> Enum.find(&issue_matches?(&1, id))
    end
  end

  defp issue_matches?(issue, id) do
    issue.id == id or to_string(issue.iid) == to_string(id) or issue.identifier == id
  end

  defp current_project_setting_id(conn) do
    case AuthPlug.current_user(conn) do
      %{local?: true} -> nil
      %{project_setting_id: project_setting_id} -> project_setting_id
      _ -> nil
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
