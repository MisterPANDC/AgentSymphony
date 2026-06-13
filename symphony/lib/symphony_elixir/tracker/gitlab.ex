defmodule SymphonyElixir.Tracker.GitLab do
  @moduledoc """
  GitLab-backed tracker adapter reading from Symphony's local read model.
  """

  @behaviour SymphonyElixir.Tracker

  alias Symphony.{GitLab.Client, GitLab.Config, GitLab.IssueMapper, GitLab.NoteMapper}
  alias SymphonyElixir.Store

  @impl true
  def fetch_candidate_issues do
    tracker = SymphonyElixir.Config.settings!().tracker
    {:ok, Store.list_candidate_tracker_issues(tracker.required_labels, tracker.active_states)}
  end

  @impl true
  def fetch_issues_by_states(statuses) do
    {:ok, Store.tracker_issues_by_workflow_statuses(statuses)}
  end

  @impl true
  def fetch_issue_states_by_ids(issue_ids) do
    {:ok, Store.tracker_issues_by_ids(issue_ids)}
  end

  @impl true
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    with {:ok, config} <- Config.load(),
         %{} = issue <- Store.get_issue(issue_id),
         {:ok, raw_note} <- Client.create_issue_note(config, issue.iid, body) do
      Store.upsert_note(issue_id, NoteMapper.from_gitlab(raw_note))
      :ok
    else
      nil -> {:error, :issue_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def update_issue_state(issue_id, status) when is_binary(issue_id) and is_binary(status) do
    case Store.transition_workflow(issue_id, status, source: "agent", actor: "agent") do
      {:ok, _workflow} ->
        maybe_close_issue(issue_id, status)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def close_issue(issue_id) when is_binary(issue_id), do: do_close_issue(issue_id)

  defp maybe_close_issue(issue_id, status) do
    if normalize_status(status) == "done" do
      do_close_issue(issue_id)
    else
      :ok
    end
  end

  defp do_close_issue(issue_id) do
    with {:ok, config} <- Config.load(),
         %{} = issue <- Store.get_issue(issue_id),
         true <- issue.gitlab_state != "closed" || :already_closed,
         {:ok, raw_issue} <- Client.update_project_issue(config, issue.iid, %{"state_event" => "close"}) do
      raw_issue |> IssueMapper.from_gitlab() |> Store.upsert_issue()
      Store.record_event("gitlab_issue_closed", "system", %{reason: "workflow done"}, issue_id: issue_id, actor: "orchestrator")
      :ok
    else
      :already_closed ->
        :ok

      nil ->
        record_close_failure(issue_id, :issue_not_found)
        {:error, :issue_not_found}

      {:error, reason} ->
        record_close_failure(issue_id, reason)
        {:error, reason}
    end
  end

  defp record_close_failure(issue_id, reason) do
    Store.record_event("gitlab_issue_close_failed", "system", %{reason: inspect(reason)}, issue_id: issue_id, actor: "orchestrator")
  rescue
    _ -> :ok
  end

  defp normalize_status(status) when is_binary(status), do: status |> String.trim() |> String.downcase()
  defp normalize_status(_status), do: ""
end
