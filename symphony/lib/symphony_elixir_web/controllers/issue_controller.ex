defmodule SymphonyElixirWeb.IssueController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias Symphony.GitLab.{Client, Config, IssueMapper}
  alias SymphonyElixir.{Store, Sync.Poller, Tracker}
  alias SymphonyElixirWeb.DTO

  @spec index(Conn.t(), map()) :: Conn.t()
  def index(conn, params) do
    filters =
      []
      |> maybe_filter(:status, params["status"])
      |> maybe_filter(:gitlab_state, params["gitlab_state"])
      |> maybe_filter(:search, params["q"])

    json(conn, %{issues: Store.list_issues(filters) |> Enum.map(&DTO.issue/1)})
  end

  @spec show(Conn.t(), map()) :: Conn.t()
  def show(conn, %{"id" => id}) do
    case find_issue(id) do
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      issue -> json(conn, %{issue: DTO.issue(issue)})
    end
  end

  @spec notes(Conn.t(), map()) :: Conn.t()
  def notes(conn, %{"id" => id}) do
    with %{} = issue <- find_issue(id) do
      Poller.sync_issue_notes(issue.id)
      json(conn, %{notes: Store.list_notes(issue.id)})
    else
      _ -> error(conn, 404, "issue_not_found", "Issue not found")
    end
  end

  @spec create_note(Conn.t(), map()) :: Conn.t()
  def create_note(conn, %{"id" => id, "body" => body}) when is_binary(body) do
    with %{} = issue <- find_issue(id),
         :ok <- Tracker.create_comment(issue.id, body) do
      json(conn, %{notes: Store.list_notes(issue.id)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "note_create_failed", inspect(reason))
    end
  end

  def create_note(conn, _params), do: error(conn, 400, "missing_body", "Note body is required")

  @spec update_gitlab(Conn.t(), map()) :: Conn.t()
  def update_gitlab(conn, %{"id" => id} = params) do
    attrs = Map.take(params, ["title", "description", "labels", "state_event", "due_date"])

    with %{} = issue <- find_issue(id),
         {:ok, config} <- Config.load(),
         {:ok, raw} <- Client.update_project_issue(config, issue.iid, attrs) do
      updated = raw |> IssueMapper.from_gitlab() |> Store.upsert_issue()
      json(conn, %{issue: DTO.issue(updated)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "gitlab_update_failed", inspect(reason))
    end
  end

  @spec update_workflow(Conn.t(), map()) :: Conn.t()
  def update_workflow(conn, %{"id" => id, "status" => status} = params) do
    with %{} = issue <- find_issue(id),
         {:ok, _workflow} <-
           Store.transition_workflow(issue.id, status,
             source: "local_ui",
             actor: "local_operator",
             reason: params["reason"]
           ),
         %{} = updated <- Store.get_issue(issue.id) do
      json(conn, %{issue: DTO.issue(updated)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "workflow_update_failed", inspect(reason))
    end
  end

  def update_workflow(conn, _params), do: error(conn, 400, "missing_status", "Workflow status is required")

  @spec events(Conn.t(), map()) :: Conn.t()
  def events(conn, %{"id" => id}) do
    case find_issue(id) do
      nil ->
        error(conn, 404, "issue_not_found", "Issue not found")

      issue ->
        json(conn, %{events: Store.list_events(issue_id: issue.id) |> Enum.map(&DTO.event/1)})
    end
  end

  defp find_issue(id) do
    Store.get_issue(id) || Store.get_issue_by_iid(id) || Store.get_issue_by_identifier(id)
  end

  defp maybe_filter(filters, _key, nil), do: filters
  defp maybe_filter(filters, _key, ""), do: filters
  defp maybe_filter(filters, key, value), do: [{key, value} | filters]

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
