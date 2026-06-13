defmodule SymphonyElixirWeb.WorkflowController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.Persistence.WorkflowState
  alias SymphonyElixir.{Store, Tracker}
  alias SymphonyElixirWeb.DTO

  @statuses WorkflowState.statuses()
  @priorities ~w(none low medium high urgent)
  @dispatch_candidate_statuses ~w(todo in_progress merging rework)

  @spec statuses(Conn.t(), map()) :: Conn.t()
  def statuses(conn, _params) do
    json(conn, %{statuses: @statuses, priorities: @priorities, dispatchCandidateStatuses: @dispatch_candidate_statuses})
  end

  @spec transition(Conn.t(), map()) :: Conn.t()
  def transition(conn, %{"issue_id" => issue_id, "status" => status} = params) do
    with %{} = issue <- find_issue(issue_id),
         {:ok, _workflow} <-
           Store.transition_workflow(issue.id, status,
             source: "local_ui",
             actor: "local_operator",
             reason: params["reason"]
           ),
         :ok <- maybe_close_done_issue(issue.id, status),
         %{} = updated <- Store.get_issue(issue.id) do
      json(conn, %{issue: DTO.issue(updated)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "transition_failed", inspect(reason))
    end
  end

  def transition(conn, _params), do: error(conn, 400, "missing_transition", "issue_id and status are required")

  @spec blockers(Conn.t(), map()) :: Conn.t()
  def blockers(conn, %{"id" => id}) do
    case find_issue(id) do
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      issue -> json(conn, %{blockers: Store.list_blockers(issue.id) |> Enum.map(&DTO.issue_ref/1)})
    end
  end

  @spec add_blocker(Conn.t(), map()) :: Conn.t()
  def add_blocker(conn, %{"id" => id, "blocking_issue_id" => blocking_id} = params) do
    with %{} = issue <- find_issue(id),
         %{} = blocking_issue <- find_issue(blocking_id),
         {:ok, _edge} <- Store.add_blocker(issue.id, blocking_issue.id, reason: params["reason"]) do
      json(conn, %{blockers: Store.list_blockers(issue.id) |> Enum.map(&DTO.issue_ref/1)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "blocker_add_failed", inspect(reason))
    end
  end

  def add_blocker(conn, _params), do: error(conn, 400, "missing_blocker", "blocking_issue_id is required")

  @spec remove_blocker(Conn.t(), map()) :: Conn.t()
  def remove_blocker(conn, %{"id" => id, "blocking_issue_id" => blocking_id}) do
    with %{} = issue <- find_issue(id),
         %{} = blocking_issue <- find_issue(blocking_id),
         :ok <- Store.remove_blocker(issue.id, blocking_issue.id) do
      json(conn, %{blockers: Store.list_blockers(issue.id) |> Enum.map(&DTO.issue_ref/1)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "blocker_remove_failed", inspect(reason))
    end
  end

  defp find_issue(id), do: Store.get_issue(id) || Store.get_issue_by_iid(id) || Store.get_issue_by_identifier(id)

  defp maybe_close_done_issue(issue_id, status) do
    if normalize_status(status) == "done", do: Tracker.close_issue(issue_id), else: :ok
    :ok
  end

  defp normalize_status(status) when is_binary(status), do: status |> String.trim() |> String.downcase()
  defp normalize_status(_status), do: ""

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
