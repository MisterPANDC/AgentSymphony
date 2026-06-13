defmodule SymphonyElixirWeb.IssueController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias Symphony.GitLab.{Client, IssueMapper, NoteMapper}
  alias Symphony.GitLab.Config, as: GitLabConfig
  alias SymphonyElixir.Store
  alias SymphonyElixirWeb.AuthPlug
  alias SymphonyElixirWeb.DTO

  @spec index(Conn.t(), map()) :: Conn.t()
  def index(conn, params) do
    case current_project_setting_id(conn) do
      nil ->
        json(conn, %{issues: []})

      project_setting_id ->
        filters =
          []
          |> maybe_filter(:status, params["status"])
          |> maybe_filter(:gitlab_state, params["gitlab_state"])
          |> maybe_filter(:search, params["q"])
          |> maybe_filter(:project_setting_id, project_setting_id)

        json(conn, %{issues: Store.list_issues(filters) |> Enum.map(&DTO.issue/1)})
    end
  end

  @spec show(Conn.t(), map()) :: Conn.t()
  def show(conn, %{"id" => id}) do
    case find_issue(conn, id) do
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      issue -> json(conn, %{issue: DTO.issue(issue)})
    end
  end

  @spec notes(Conn.t(), map()) :: Conn.t()
  def notes(conn, %{"id" => id}) do
    with %{} = issue <- find_issue(conn, id),
         {:ok, _notes} <- sync_issue_notes(conn, issue) do
      json(conn, %{notes: Store.list_notes(issue.id)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "note_sync_failed", inspect(reason))
    end
  end

  @spec create_note(Conn.t(), map()) :: Conn.t()
  def create_note(conn, %{"id" => id, "body" => body}) when is_binary(body) do
    with %{} = issue <- find_issue(conn, id),
         :ok <- create_user_note(conn, issue, body) do
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

    with %{} = issue <- find_issue(conn, id),
         {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
         {:ok, raw} <- Client.update_project_issue(config, issue.iid, attrs, auth_opts) do
      updated = raw |> IssueMapper.from_gitlab() |> Store.upsert_issue()
      json(conn, %{issue: DTO.issue(updated)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "gitlab_update_failed", inspect(reason))
    end
  end

  @spec update_workflow(Conn.t(), map()) :: Conn.t()
  def update_workflow(conn, %{"id" => id, "status" => status} = params) do
    with %{} = issue <- find_issue(conn, id),
         {:ok, _workflow} <-
           Store.transition_workflow(issue.id, status,
             source: "user_ui",
             actor: AuthPlug.actor(conn),
             reason: params["reason"]
           ),
         :ok <- maybe_close_done_issue(conn, issue, status),
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
    case find_issue(conn, id) do
      nil ->
        error(conn, 404, "issue_not_found", "Issue not found")

      issue ->
        json(conn, %{events: Store.list_events(issue_id: issue.id) |> Enum.map(&DTO.event/1)})
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

  defp maybe_filter(filters, _key, nil), do: filters
  defp maybe_filter(filters, _key, ""), do: filters
  defp maybe_filter(filters, key, value), do: [{key, value} | filters]

  defp sync_issue_notes(conn, issue) do
    with {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
         {:ok, raw_notes} <- Client.list_issue_notes(config, issue.iid, %{per_page: config.sync_page_size}, auth_opts) do
      notes = Enum.map(raw_notes, &Store.upsert_note(issue.id, NoteMapper.from_gitlab(&1)))
      {:ok, notes}
    end
  end

  defp create_user_note(conn, issue, body) do
    with {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
         {:ok, raw_note} <- Client.create_issue_note(config, issue.iid, body, auth_opts) do
      Store.upsert_note(issue.id, NoteMapper.from_gitlab(raw_note))
      :ok
    end
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
