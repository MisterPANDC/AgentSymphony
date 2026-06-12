defmodule SymphonyElixir.Store do
  @moduledoc """
  Persistence facade for GitLab-backed Symphony state.

  The GitLab migration uses PostgreSQL through `SymphonyElixir.Store.Postgres`
  when a database URL or explicit backend setting is present. A JSON fallback is
  kept for local development on machines without PostgreSQL.
  """

  @type backend :: SymphonyElixir.Store.Postgres | SymphonyElixir.Store.Json

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: backend().start_link(opts)

  @spec backend() :: backend()
  def backend do
    case configured_backend() do
      :postgres -> SymphonyElixir.Store.Postgres
      :json -> SymphonyElixir.Store.Json
    end
  end

  @spec configured_backend() :: :postgres | :json
  def configured_backend do
    configured =
      System.get_env("SYMPHONY_STORE_BACKEND") ||
        Application.get_env(:symphony_elixir, :store_backend)

    cond do
      configured in ["postgres", :postgres] ->
        :postgres

      configured in ["json", :json] ->
        :json

      database_url?() ->
        :postgres

      true ->
        :json
    end
  end

  defp database_url? do
    present?(System.get_env("SYMPHONY_DATABASE_URL")) or present?(System.get_env("DATABASE_URL"))
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  @spec upsert_project(map()) :: map()
  def upsert_project(attrs), do: backend().upsert_project(attrs)

  @spec project() :: map() | nil
  def project, do: backend().project()

  @spec upsert_issue(map()) :: map()
  def upsert_issue(attrs), do: backend().upsert_issue(attrs)

  @spec list_issues(keyword()) :: [map()]
  def list_issues(filters \\ []), do: backend().list_issues(filters)

  @spec get_issue(String.t()) :: map() | nil
  def get_issue(id), do: backend().get_issue(id)

  @spec get_issue_by_iid(integer() | String.t()) :: map() | nil
  def get_issue_by_iid(iid), do: backend().get_issue_by_iid(iid)

  @spec get_issue_by_identifier(String.t()) :: map() | nil
  def get_issue_by_identifier(identifier), do: backend().get_issue_by_identifier(identifier)

  @spec issue_to_tracker(map()) :: SymphonyElixir.Tracker.Issue.t()
  def issue_to_tracker(issue), do: backend().issue_to_tracker(issue)

  @spec list_candidate_tracker_issues([String.t()]) :: [SymphonyElixir.Tracker.Issue.t()]
  def list_candidate_tracker_issues(required_labels), do: backend().list_candidate_tracker_issues(required_labels)

  @spec tracker_issues_by_ids([String.t()]) :: [SymphonyElixir.Tracker.Issue.t()]
  def tracker_issues_by_ids(issue_ids), do: backend().tracker_issues_by_ids(issue_ids)

  @spec tracker_issues_by_workflow_statuses([String.t()]) :: [SymphonyElixir.Tracker.Issue.t()]
  def tracker_issues_by_workflow_statuses(statuses), do: backend().tracker_issues_by_workflow_statuses(statuses)

  @spec transition_workflow(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def transition_workflow(issue_id, status, opts \\ []), do: backend().transition_workflow(issue_id, status, opts)

  @spec update_priority(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def update_priority(issue_id, priority), do: backend().update_priority(issue_id, priority)

  @spec list_blockers(String.t()) :: [map()]
  def list_blockers(issue_id), do: backend().list_blockers(issue_id)

  @spec add_blocker(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add_blocker(blocked_issue_id, blocking_issue_id, opts \\ []), do: backend().add_blocker(blocked_issue_id, blocking_issue_id, opts)

  @spec remove_blocker(String.t(), String.t()) :: :ok | {:error, term()}
  def remove_blocker(blocked_issue_id, blocking_issue_id), do: backend().remove_blocker(blocked_issue_id, blocking_issue_id)

  @spec upsert_note(String.t(), map()) :: map()
  def upsert_note(issue_id, attrs), do: backend().upsert_note(issue_id, attrs)

  @spec list_notes(String.t()) :: [map()]
  def list_notes(issue_id), do: backend().list_notes(issue_id)

  @spec list_events(keyword()) :: [map()]
  def list_events(filters \\ []), do: backend().list_events(filters)

  @spec record_event(String.t(), String.t(), map(), keyword()) :: map()
  def record_event(event_type, source, payload \\ %{}, opts \\ []), do: backend().record_event(event_type, source, payload, opts)

  @spec put_cursor(String.t(), String.t(), map()) :: map()
  def put_cursor(source, cursor_name, attrs), do: backend().put_cursor(source, cursor_name, attrs)

  @spec cursors() :: map()
  def cursors, do: backend().cursors()

  @spec create_run(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_run(issue_id, attrs \\ %{}), do: backend().create_run(issue_id, attrs)

  @spec update_run(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_run(run_id, attrs), do: backend().update_run(run_id, attrs)

  @spec list_runs(keyword()) :: [map()]
  def list_runs(filters \\ []), do: backend().list_runs(filters)

  @spec get_run(String.t()) :: map() | nil
  def get_run(run_id), do: backend().get_run(run_id)

  @spec add_run_event(String.t(), String.t(), String.t() | nil, map()) :: {:ok, map()} | {:error, term()}
  def add_run_event(run_id, event_type, message \\ nil, payload \\ %{}), do: backend().add_run_event(run_id, event_type, message, payload)

  @spec list_run_events(String.t()) :: [map()]
  def list_run_events(run_id), do: backend().list_run_events(run_id)

  @spec create_runtime_block(String.t(), String.t(), String.t() | nil, map(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def create_runtime_block(issue_id, block_type, message, payload \\ %{}, run_id \\ nil),
    do: backend().create_runtime_block(issue_id, block_type, message, payload, run_id)

  @spec resolve_runtime_block(String.t()) :: {:ok, map()} | {:error, term()}
  def resolve_runtime_block(block_id), do: backend().resolve_runtime_block(block_id)

  @spec list_open_runtime_blocks() :: [map()]
  def list_open_runtime_blocks, do: backend().list_open_runtime_blocks()

  @spec snapshot() :: map()
  def snapshot, do: backend().snapshot()
end
