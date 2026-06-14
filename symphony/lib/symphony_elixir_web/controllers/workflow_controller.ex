defmodule SymphonyElixirWeb.WorkflowController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias Symphony.GitLab.{Client, IssueMapper}
  alias Symphony.GitLab.Config, as: GitLabConfig
  alias SymphonyElixir.Store
  alias SymphonyElixir.Workflow.Transitions
  alias SymphonyElixirWeb.AuthPlug
  alias SymphonyElixirWeb.DTO
  alias SymphonyElixirWeb.WorkflowTransition

  @statuses Transitions.statuses()
  @priorities ~w(none low medium high urgent)
  @dispatch_candidate_statuses Transitions.dispatch_candidate_statuses()

  @spec statuses(Conn.t(), map()) :: Conn.t()
  def statuses(conn, _params) do
    json(conn, %{
      statuses: @statuses,
      priorities: @priorities,
      dispatchCandidateStatuses: @dispatch_candidate_statuses,
      userTransitionTargets: Map.new(@statuses, &{&1, Transitions.user_targets(&1)})
    })
  end

  @spec transition(Conn.t(), map()) :: Conn.t()
  def transition(conn, %{"issue_id" => issue_id, "status" => status} = params) do
    actor = AuthPlug.actor(conn)

    with %{} = issue <- find_issue(conn, issue_id),
         :ok <- WorkflowTransition.require_active_run_stop_confirmation(issue, status, params),
         {:ok, _workflow} <-
           Store.transition_workflow(issue.id, status,
             source: "user_ui",
             actor: actor,
             reason: params["reason"]
           ),
         :ok <- WorkflowTransition.maybe_stop_active_run(issue, status, actor),
         :ok <- maybe_close_done_issue(conn, issue, status),
         %{} = updated <- Store.get_issue(issue.id) do
      json(conn, %{issue: DTO.issue(updated)})
    else
      nil ->
        error(conn, 404, "issue_not_found", "Issue not found")

      {:error, :active_run_stop_confirmation_required} ->
        error(conn, 409, "active_run_stop_confirmation_required", "Changing to this status will stop the active run. Confirm the transition to continue.")

      {:error, reason} ->
        error(conn, 422, "transition_failed", inspect(reason))
    end
  end

  def transition(conn, _params), do: error(conn, 400, "missing_transition", "issue_id and status are required")

  @spec blockers(Conn.t(), map()) :: Conn.t()
  def blockers(conn, %{"id" => id}) do
    case find_issue(conn, id) do
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      issue -> json(conn, %{blockers: Store.list_blockers(issue.id) |> Enum.map(&DTO.issue_ref/1)})
    end
  end

  @spec add_blocker(Conn.t(), map()) :: Conn.t()
  def add_blocker(conn, %{"id" => id, "blocking_issue_id" => blocking_id} = params) do
    with %{} = issue <- find_issue(conn, id),
         %{} = blocking_issue <- find_issue(conn, blocking_id),
         {:ok, _edge} <- Store.add_blocker(issue.id, blocking_issue.id, actor: AuthPlug.actor(conn), reason: params["reason"]) do
      json(conn, %{blockers: Store.list_blockers(issue.id) |> Enum.map(&DTO.issue_ref/1)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "blocker_add_failed", inspect(reason))
    end
  end

  def add_blocker(conn, _params), do: error(conn, 400, "missing_blocker", "blocking_issue_id is required")

  @spec remove_blocker(Conn.t(), map()) :: Conn.t()
  def remove_blocker(conn, %{"id" => id, "blocking_issue_id" => blocking_id}) do
    with %{} = issue <- find_issue(conn, id),
         %{} = blocking_issue <- find_issue(conn, blocking_id),
         :ok <- Store.remove_blocker(issue.id, blocking_issue.id) do
      json(conn, %{blockers: Store.list_blockers(issue.id) |> Enum.map(&DTO.issue_ref/1)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "blocker_remove_failed", inspect(reason))
    end
  end

  defp find_issue(conn, id) do
    case current_project_setting_id(conn) do
      nil ->
        nil

      project_id ->
        Store.list_issues(project_setting_id: project_id)
        |> Enum.find(&issue_matches?(&1, id))
    end
  end

  defp issue_matches?(issue, id) do
    issue.id == id or to_string(issue.iid) == to_string(id) or issue.identifier == id
  end

  defp maybe_close_done_issue(conn, issue, status) do
    if normalize_status(status) == "done" do
      close_user_issue(conn, issue)
    else
      :ok
    end
  end

  defp close_user_issue(_conn, %{gitlab_state: "closed"}), do: :ok

  defp close_user_issue(conn, issue) do
    with {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
         {:ok, raw_issue} <- Client.update_project_issue(config, issue.iid, %{"state_event" => "close"}, auth_opts) do
      raw_issue |> IssueMapper.from_gitlab() |> Store.upsert_issue()
      Store.record_event("gitlab_issue_closed", "user_ui", %{reason: "workflow done"}, issue_id: issue.id, actor: AuthPlug.actor(conn))
      :ok
    end
  end

  defp user_gitlab_context(conn, issue) do
    with {:ok, access_token} <- AuthPlug.oauth_access_token(conn),
         {:ok, config} <- project_config_for_issue(issue) do
      {:ok, config, [auth: {:bearer, access_token}]}
    end
  end

  defp project_config_for_issue(issue) do
    with project_id when is_binary(project_id) <- Map.get(issue, :gitlab_project_setting_id),
         %{} = project <- Store.project_by_id(project_id) do
      GitLabConfig.from_project_setting(project)
    else
      _ -> {:error, :project_not_found}
    end
  end

  defp current_project_setting_id(conn) do
    case AuthPlug.current_user(conn) do
      %{project_setting_id: project_setting_id} -> project_setting_id
      _ -> nil
    end
  end

  defp normalize_status(status) when is_binary(status), do: status |> String.trim() |> String.downcase()
  defp normalize_status(_status), do: ""

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
