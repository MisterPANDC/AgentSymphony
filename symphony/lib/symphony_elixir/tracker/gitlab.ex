defmodule SymphonyElixir.Tracker.GitLab do
  @moduledoc """
  GitLab-backed tracker adapter reading from Symphony's local read model.
  """

  @behaviour SymphonyElixir.Tracker

  alias Symphony.{GitLab.Client, GitLab.Config, GitLab.NoteMapper}
  alias SymphonyElixir.Store

  @impl true
  def fetch_candidate_issues do
    required_labels = SymphonyElixir.Config.settings!().tracker.required_labels
    {:ok, Store.list_candidate_tracker_issues(required_labels)}
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
      {:ok, _workflow} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
