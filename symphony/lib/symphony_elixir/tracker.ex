defmodule SymphonyElixir.Tracker do
  @moduledoc """
  Adapter boundary for GitLab-native issue tracker reads and writes.
  """

  alias SymphonyElixir.Config

  @callback fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  @callback create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  @callback update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  @callback sync_issue_lifecycle(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  @callback create_followup_issue(String.t(), map()) :: {:ok, map()} | {:error, term()}
  @callback close_issue(String.t()) :: :ok | {:error, term()}

  @spec fetch_candidate_issues() :: {:ok, [term()]} | {:error, term()}
  def fetch_candidate_issues do
    adapter().fetch_candidate_issues()
  end

  @spec fetch_issues_by_states([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issues_by_states(states) do
    adapter().fetch_issues_by_states(states)
  end

  @spec fetch_issue_states_by_ids([String.t()]) :: {:ok, [term()]} | {:error, term()}
  def fetch_issue_states_by_ids(issue_ids) do
    adapter().fetch_issue_states_by_ids(issue_ids)
  end

  @spec create_comment(String.t(), String.t()) :: :ok | {:error, term()}
  def create_comment(issue_id, body) do
    adapter().create_comment(issue_id, body)
  end

  @spec update_issue_state(String.t(), String.t()) :: :ok | {:error, term()}
  def update_issue_state(issue_id, state_name) do
    adapter().update_issue_state(issue_id, state_name)
  end

  @spec sync_issue_lifecycle(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def sync_issue_lifecycle(issue_id, previous_state_name, state_name) do
    adapter().sync_issue_lifecycle(issue_id, previous_state_name, state_name)
  end

  @spec create_followup_issue(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_followup_issue(current_issue_id, attrs) do
    adapter().create_followup_issue(current_issue_id, attrs)
  end

  @spec close_issue(String.t()) :: :ok | {:error, term()}
  def close_issue(issue_id) do
    adapter().close_issue(issue_id)
  end

  @spec adapter() :: module()
  def adapter do
    case Config.settings!().tracker.kind do
      "memory" -> SymphonyElixir.Tracker.Memory
      "gitlab" -> SymphonyElixir.Tracker.GitLab
      _ -> SymphonyElixir.Tracker.GitLab
    end
  end
end
