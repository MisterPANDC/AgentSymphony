defmodule SymphonyElixir.Store.Json do
  @moduledoc """
  Local JSON fallback state for GitLab-backed Symphony.

  PostgreSQL is the conforming persistence backend. This module is retained as
  a local fallback for development environments that have not configured a
  database yet.
  """

  use GenServer

  alias SymphonyElixir.Tracker.Issue

  @workflow_statuses ~w(triage todo in_progress blocked review done canceled)
  @priorities ~w(none low medium high urgent)
  @run_statuses ~w(queued starting running blocked succeeded failed canceled stale)
  @block_types ~w(operator_input approval_required mcp_elicitation sandbox_rejection external_failure blocked_by_dependency)
  @event_sources ~w(gitlab_sync local_ui agent system)

  defstruct [
    :path,
    :started_at,
    :project,
    issues: %{},
    issue_order: [],
    issue_by_iid: %{},
    issue_by_gitlab_id: %{},
    workflow_states: %{},
    dependencies: %{},
    notes: %{},
    events: [],
    cursors: %{},
    runs: %{},
    run_order: [],
    run_events: %{},
    runtime_blocks: %{}
  ]

  @type t :: %__MODULE__{}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    path = Keyword.get(opts, :path) || Application.get_env(:symphony_elixir, :store_path) || default_path()
    File.mkdir_p!(Path.dirname(path))

    state =
      path
      |> load_state()
      |> Map.put(:path, path)
      |> Map.put_new(:started_at, DateTime.utc_now())
      |> struct_state()

    {:ok, state}
  end

  @spec upsert_project(map()) :: map()
  def upsert_project(attrs), do: call({:upsert_project, attrs})

  @spec project() :: map() | nil
  def project, do: call(:project)

  @spec upsert_issue(map()) :: map()
  def upsert_issue(attrs), do: call({:upsert_issue, attrs})

  @spec list_issues(keyword()) :: [map()]
  def list_issues(filters \\ []), do: call({:list_issues, filters})

  @spec get_issue(String.t()) :: map() | nil
  def get_issue(id), do: call({:get_issue, id})

  @spec get_issue_by_iid(integer() | String.t()) :: map() | nil
  def get_issue_by_iid(iid), do: call({:get_issue_by_iid, iid})

  @spec get_issue_by_identifier(String.t()) :: map() | nil
  def get_issue_by_identifier(identifier), do: call({:get_issue_by_identifier, identifier})

  @spec issue_to_tracker(map()) :: Issue.t()
  def issue_to_tracker(issue), do: call({:issue_to_tracker, issue})

  @spec list_candidate_tracker_issues([String.t()]) :: [Issue.t()]
  def list_candidate_tracker_issues(required_labels), do: call({:list_candidate_tracker_issues, required_labels})

  @spec tracker_issues_by_ids([String.t()]) :: [Issue.t()]
  def tracker_issues_by_ids(ids), do: call({:tracker_issues_by_ids, ids})

  @spec tracker_issues_by_workflow_statuses([String.t()]) :: [Issue.t()]
  def tracker_issues_by_workflow_statuses(statuses), do: call({:tracker_issues_by_workflow_statuses, statuses})

  @spec transition_workflow(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def transition_workflow(issue_id, status, opts \\ []), do: call({:transition_workflow, issue_id, status, opts})

  @spec update_priority(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def update_priority(issue_id, priority), do: call({:update_priority, issue_id, priority})

  @spec list_blockers(String.t()) :: [map()]
  def list_blockers(issue_id), do: call({:list_blockers, issue_id})

  @spec add_blocker(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add_blocker(blocked_issue_id, blocking_issue_id, opts \\ []),
    do: call({:add_blocker, blocked_issue_id, blocking_issue_id, opts})

  @spec remove_blocker(String.t(), String.t()) :: :ok | {:error, term()}
  def remove_blocker(blocked_issue_id, blocking_issue_id), do: call({:remove_blocker, blocked_issue_id, blocking_issue_id})

  @spec upsert_note(String.t(), map()) :: map()
  def upsert_note(issue_id, attrs), do: call({:upsert_note, issue_id, attrs})

  @spec list_notes(String.t()) :: [map()]
  def list_notes(issue_id), do: call({:list_notes, issue_id})

  @spec list_events(keyword()) :: [map()]
  def list_events(filters \\ []), do: call({:list_events, filters})

  @spec record_event(String.t(), String.t(), map(), keyword()) :: map()
  def record_event(event_type, source, payload \\ %{}, opts \\ []),
    do: call({:record_event, event_type, source, payload, opts})

  @spec put_cursor(String.t(), String.t(), map()) :: map()
  def put_cursor(source, cursor_name, attrs), do: call({:put_cursor, source, cursor_name, attrs})

  @spec cursors() :: map()
  def cursors, do: call(:cursors)

  @spec create_run(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_run(issue_id, attrs \\ %{}), do: call({:create_run, issue_id, attrs})

  @spec update_run(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_run(run_id, attrs), do: call({:update_run, run_id, attrs})

  @spec list_runs(keyword()) :: [map()]
  def list_runs(filters \\ []), do: call({:list_runs, filters})

  @spec get_run(String.t()) :: map() | nil
  def get_run(run_id), do: call({:get_run, run_id})

  @spec add_run_event(String.t(), String.t(), String.t() | nil, map()) :: {:ok, map()} | {:error, term()}
  def add_run_event(run_id, event_type, message \\ nil, payload \\ %{}),
    do: call({:add_run_event, run_id, event_type, message, payload})

  @spec list_run_events(String.t()) :: [map()]
  def list_run_events(run_id), do: call({:list_run_events, run_id})

  @spec create_runtime_block(String.t(), String.t(), String.t() | nil, map(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def create_runtime_block(issue_id, block_type, message, payload \\ %{}, run_id \\ nil),
    do: call({:create_runtime_block, issue_id, block_type, message, payload, run_id})

  @spec resolve_runtime_block(String.t()) :: {:ok, map()} | {:error, term()}
  def resolve_runtime_block(block_id), do: call({:resolve_runtime_block, block_id})

  @spec list_open_runtime_blocks() :: [map()]
  def list_open_runtime_blocks, do: call(:list_open_runtime_blocks)

  @spec snapshot() :: map()
  def snapshot, do: call(:snapshot)

  @impl true
  def handle_call({:upsert_project, attrs}, _from, state) do
    now = now()
    project = normalize_project(attrs, state.project, now)
    state = persist(%{state | project: project})
    {:reply, project, state}
  end

  def handle_call(:project, _from, state), do: {:reply, state.project, state}

  def handle_call({:upsert_issue, attrs}, _from, state) do
    now = now()
    local_id = issue_local_id(attrs)
    existing = Map.get(state.issues, local_id, %{})
    issue = normalize_issue(attrs, existing, now)
    workflow_state = Map.get(state.workflow_states, local_id) || default_workflow_state(local_id, now)

    state =
      state
      |> put_in([Access.key(:issues), local_id], issue)
      |> put_issue_indexes(issue)
      |> put_issue_order(local_id)
      |> put_in([Access.key(:workflow_states), local_id], workflow_state)
      |> append_event("gitlab_issue_synced", "gitlab_sync", %{iid: issue.iid, title: issue.title}, issue_id: local_id)
      |> persist()

    {:reply, decorate_issue(state, issue), state}
  end

  def handle_call({:list_issues, filters}, _from, state) do
    issues =
      state.issue_order
      |> Enum.map(&Map.get(state.issues, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&decorate_issue(state, &1))
      |> apply_issue_filters(filters)

    {:reply, issues, state}
  end

  def handle_call({:get_issue, id}, _from, state) do
    {:reply, state.issues |> Map.get(id) |> maybe_decorate_issue(state), state}
  end

  def handle_call({:get_issue_by_iid, iid}, _from, state) do
    id = Map.get(state.issue_by_iid, to_string(iid))
    {:reply, id && state.issues |> Map.get(id) |> maybe_decorate_issue(state), state}
  end

  def handle_call({:get_issue_by_identifier, identifier}, _from, state) do
    issue =
      state.issues
      |> Map.values()
      |> Enum.find(&(issue_identifier(state, &1) == identifier))
      |> maybe_decorate_issue(state)

    {:reply, issue, state}
  end

  def handle_call({:issue_to_tracker, issue}, _from, state) do
    {:reply, tracker_issue(state, undecorate(issue)), state}
  end

  def handle_call({:list_candidate_tracker_issues, required_labels}, _from, state) do
    issues =
      state.issue_order
      |> Enum.map(&Map.get(state.issues, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn issue ->
        workflow = Map.get(state.workflow_states, issue.id, %{})

        issue.gitlab_state == "opened" and workflow.status == "todo" and
          not unresolved_dependency?(state, issue.id) and labels_satisfy?(issue.labels, required_labels) and
          no_active_run?(state, issue.id)
      end)
      |> Enum.map(&tracker_issue(state, &1))

    {:reply, issues, state}
  end

  def handle_call({:tracker_issues_by_ids, ids}, _from, state) do
    wanted = MapSet.new(ids)

    issues =
      state.issue_order
      |> Enum.map(&Map.get(state.issues, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(&MapSet.member?(wanted, &1.id))
      |> Enum.map(&tracker_issue(state, &1))

    {:reply, issues, state}
  end

  def handle_call({:tracker_issues_by_workflow_statuses, statuses}, _from, state) do
    wanted = MapSet.new(Enum.map(statuses, &normalize_status/1))

    issues =
      state.issue_order
      |> Enum.map(&Map.get(state.issues, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn issue ->
        workflow = Map.get(state.workflow_states, issue.id, %{})
        MapSet.member?(wanted, workflow.status)
      end)
      |> Enum.map(&tracker_issue(state, &1))

    {:reply, issues, state}
  end

  def handle_call({:transition_workflow, issue_id, next_status, opts}, _from, state) do
    case transition(state, issue_id, next_status, opts) do
      {:ok, workflow, state} ->
        {:reply, {:ok, workflow}, persist(state)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:update_priority, issue_id, priority}, _from, state) do
    priority = normalize_priority(priority)

    cond do
      not Map.has_key?(state.workflow_states, issue_id) ->
        {:reply, {:error, :issue_not_found}, state}

      priority not in @priorities ->
        {:reply, {:error, :invalid_priority}, state}

      true ->
        workflow = Map.get(state.workflow_states, issue_id) |> Map.put(:priority, priority)

        state =
          state
          |> put_in([Access.key(:workflow_states), issue_id], workflow)
          |> append_event("workflow_priority_changed", "local_ui", %{priority: priority}, issue_id: issue_id)
          |> persist()

        {:reply, {:ok, workflow}, state}
    end
  end

  def handle_call({:list_blockers, issue_id}, _from, state) do
    {:reply, blocker_dtos(state, issue_id), state}
  end

  def handle_call({:add_blocker, blocked_issue_id, blocking_issue_id, opts}, _from, state) do
    result =
      cond do
        blocked_issue_id == blocking_issue_id ->
          {:error, :self_dependency}

        not Map.has_key?(state.issues, blocked_issue_id) or not Map.has_key?(state.issues, blocking_issue_id) ->
          {:error, :issue_not_found}

        dependency_path?(state, blocking_issue_id, blocked_issue_id) ->
          {:error, :dependency_cycle}

        true ->
          edge = %{
            id: Ecto.UUID.generate(),
            blocked_issue_id: blocked_issue_id,
            blocking_issue_id: blocking_issue_id,
            created_by: Keyword.get(opts, :actor, "local_operator"),
            reason: Keyword.get(opts, :reason),
            inserted_at: now(),
            updated_at: now()
          }

          state =
            state
            |> put_in([Access.key(:dependencies), dependency_key(blocked_issue_id, blocking_issue_id)], edge)
            |> append_event("dependency_added", "local_ui", Map.take(edge, [:blocking_issue_id, :reason]), issue_id: blocked_issue_id)
            |> persist()

          {:ok, edge, state}
      end

    case result do
      {:ok, edge, state} -> {:reply, {:ok, edge}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:remove_blocker, blocked_issue_id, blocking_issue_id}, _from, state) do
    key = dependency_key(blocked_issue_id, blocking_issue_id)

    if Map.has_key?(state.dependencies, key) do
      state =
        state
        |> update_in([Access.key(:dependencies)], &Map.delete(&1, key))
        |> append_event("dependency_removed", "local_ui", %{blocking_issue_id: blocking_issue_id}, issue_id: blocked_issue_id)
        |> persist()

      {:reply, :ok, state}
    else
      {:reply, {:error, :dependency_not_found}, state}
    end
  end

  def handle_call({:upsert_note, issue_id, attrs}, _from, state) do
    now = now()
    note = normalize_note(issue_id, attrs, now)
    notes = Map.get(state.notes, issue_id, [])
    notes = [note | Enum.reject(notes, &(&1.note_id == note.note_id))]

    state =
      state
      |> put_in([Access.key(:notes), issue_id], sort_notes(notes))
      |> append_event("gitlab_note_synced", "gitlab_sync", %{note_id: note.note_id}, issue_id: issue_id)
      |> persist()

    {:reply, note, state}
  end

  def handle_call({:list_notes, issue_id}, _from, state), do: {:reply, Map.get(state.notes, issue_id, []), state}

  def handle_call({:list_events, filters}, _from, state) do
    {:reply, apply_event_filters(state.events, filters), state}
  end

  def handle_call({:record_event, event_type, source, payload, opts}, _from, state) do
    state = append_event(state, event_type, source, payload, opts) |> persist()
    {:reply, hd(state.events), state}
  end

  def handle_call({:put_cursor, source, cursor_name, attrs}, _from, state) do
    now = now()
    key = cursor_key(source, cursor_name)

    cursor =
      state.cursors
      |> Map.get(key, %{id: Ecto.UUID.generate(), source: source, cursor_name: cursor_name, inserted_at: now})
      |> Map.merge(Map.new(attrs))
      |> Map.put(:updated_at, now)

    state = put_in(state.cursors[key], cursor) |> persist()
    {:reply, cursor, state}
  end

  def handle_call(:cursors, _from, state), do: {:reply, state.cursors, state}

  def handle_call({:create_run, issue_id, attrs}, _from, state) do
    if Map.has_key?(state.issues, issue_id) do
      now = now()
      run_number = next_run_number(state, issue_id)
      run = normalize_run(issue_id, run_number, attrs, now)

      state =
        state
        |> put_in([Access.key(:runs), run.id], run)
        |> update_in([Access.key(:run_order)], &(&1 ++ [run.id]))
        |> append_event("agent_run_created", "agent", %{run_id: run.id, status: run.status}, issue_id: issue_id)
        |> persist()

      {:reply, {:ok, run}, state}
    else
      {:reply, {:error, :issue_not_found}, state}
    end
  end

  def handle_call({:update_run, run_id, attrs}, _from, state) do
    case Map.get(state.runs, run_id) do
      nil ->
        {:reply, {:error, :run_not_found}, state}

      run ->
        run = run |> Map.merge(Map.new(attrs)) |> Map.put(:updated_at, now())
        state = put_in(state.runs[run_id], run) |> persist()
        {:reply, {:ok, run}, state}
    end
  end

  def handle_call({:list_runs, filters}, _from, state) do
    runs =
      state.run_order
      |> Enum.map(&Map.get(state.runs, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&decorate_run(state, &1))
      |> apply_run_filters(filters)

    {:reply, runs, state}
  end

  def handle_call({:get_run, run_id}, _from, state) do
    {:reply, state.runs |> Map.get(run_id) |> maybe_decorate_run(state), state}
  end

  def handle_call({:add_run_event, run_id, event_type, message, payload}, _from, state) do
    if Map.has_key?(state.runs, run_id) do
      event = %{
        id: Ecto.UUID.generate(),
        agent_run_id: run_id,
        event_type: event_type,
        message: message,
        payload: payload || %{},
        inserted_at: now()
      }

      state =
        state
        |> update_in([Access.key(:run_events)], fn events ->
          Map.update(events, run_id, [event], &[event | &1])
        end)
        |> persist()

      {:reply, {:ok, event}, state}
    else
      {:reply, {:error, :run_not_found}, state}
    end
  end

  def handle_call({:list_run_events, run_id}, _from, state) do
    {:reply, state.run_events |> Map.get(run_id, []) |> Enum.reverse(), state}
  end

  def handle_call({:create_runtime_block, issue_id, block_type, message, payload, run_id}, _from, state) do
    cond do
      block_type not in @block_types ->
        {:reply, {:error, :invalid_block_type}, state}

      not Map.has_key?(state.issues, issue_id) ->
        {:reply, {:error, :issue_not_found}, state}

      true ->
        now = now()

        block = %{
          id: Ecto.UUID.generate(),
          gitlab_issue_id: issue_id,
          agent_run_id: run_id,
          block_type: block_type,
          message: message,
          payload: payload || %{},
          resolved_at: nil,
          inserted_at: now,
          updated_at: now
        }

        state =
          state
          |> put_in([Access.key(:runtime_blocks), block.id], block)
          |> append_event("runtime_block_created", "system", %{block_id: block.id, block_type: block_type}, issue_id: issue_id, run_id: run_id)
          |> persist()

        {:reply, {:ok, block}, state}
    end
  end

  def handle_call({:resolve_runtime_block, block_id}, _from, state) do
    case Map.get(state.runtime_blocks, block_id) do
      nil ->
        {:reply, {:error, :block_not_found}, state}

      block ->
        block = %{block | resolved_at: now(), updated_at: now()}

        state =
          state
          |> put_in([Access.key(:runtime_blocks), block_id], block)
          |> append_event("runtime_block_resolved", "local_ui", %{block_id: block.id}, issue_id: block.gitlab_issue_id, run_id: block.agent_run_id)
          |> persist()

        {:reply, {:ok, block}, state}
    end
  end

  def handle_call(:list_open_runtime_blocks, _from, state) do
    blocks =
      state.runtime_blocks
      |> Map.values()
      |> Enum.reject(& &1.resolved_at)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})
      |> Enum.map(&decorate_block(state, &1))

    {:reply, blocks, state}
  end

  def handle_call(:snapshot, _from, state), do: {:reply, to_snapshot(state), state}

  defp call(message), do: GenServer.call(__MODULE__, message, 15_000)

  defp default_path, do: Path.expand(".symphony/state.json")

  defp load_state(path) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> Jason.decode!(keys: :atoms)
        |> hydrate_state()

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp hydrate_state(map) when is_map(map) do
    map
    |> update_map_values(:issues, &hydrate_issue/1)
    |> update_map_values(:workflow_states, &hydrate_datetime_fields(&1, [:claimed_at, :last_transition_at, :inserted_at, :updated_at]))
    |> update_map_values(:dependencies, &hydrate_datetime_fields(&1, [:inserted_at, :updated_at]))
    |> update_map_values(:runs, &hydrate_datetime_fields(&1, [:started_at, :finished_at, :last_heartbeat_at, :inserted_at, :updated_at]))
    |> update_map_values(:runtime_blocks, &hydrate_datetime_fields(&1, [:resolved_at, :inserted_at, :updated_at]))
    |> update_map_values(:cursors, &hydrate_datetime_fields(&1, [:last_success_at, :last_attempt_at, :last_error_at, :inserted_at, :updated_at]))
    |> update_notes()
    |> update_events()
    |> update_run_events()
  end

  defp struct_state(map) do
    struct(__MODULE__, Map.merge(%__MODULE__{} |> Map.from_struct(), map))
  end

  defp persist(%__MODULE__{} = state) do
    state.path
    |> Path.dirname()
    |> File.mkdir_p!()

    encoded =
      state
      |> Map.from_struct()
      |> Map.drop([:path])
      |> Jason.encode!(pretty: true)

    File.write!(state.path, encoded)
    state
  end

  defp normalize_project(attrs, existing, now) do
    existing = existing || %{id: Ecto.UUID.generate(), inserted_at: now}

    existing
    |> Map.merge(Map.new(attrs))
    |> Map.put_new(:id, Ecto.UUID.generate())
    |> Map.put(:updated_at, now)
    |> Map.put_new(:inserted_at, now)
  end

  defp issue_local_id(attrs) do
    project_id = attrs[:gitlab_project_id] || attrs["gitlab_project_id"] || attrs[:project_id] || attrs["project_id"]
    iid = attrs[:iid] || attrs["iid"]
    "gitlab-#{project_id}-#{iid}"
  end

  defp normalize_issue(attrs, existing, now) do
    attrs = Map.new(attrs)
    local_id = issue_local_id(attrs)

    existing
    |> Map.merge(attrs)
    |> Map.put(:id, local_id)
    |> Map.put_new(:inserted_at, now)
    |> Map.put(:updated_at, now)
    |> Map.update(:labels, [], &(&1 || []))
    |> Map.update(:assignees, [], &(&1 || []))
  end

  defp default_workflow_state(issue_id, now) do
    %{
      id: Ecto.UUID.generate(),
      gitlab_issue_id: issue_id,
      status: "triage",
      priority: "none",
      rank: nil,
      claimed_by: nil,
      claimed_at: nil,
      last_transition_at: now,
      last_transition_reason: "synced from GitLab",
      inserted_at: now,
      updated_at: now
    }
  end

  defp normalize_note(issue_id, attrs, now) do
    attrs = Map.new(attrs)

    attrs
    |> Map.put(:id, "note-#{issue_id}-#{attrs[:note_id] || attrs["note_id"]}")
    |> Map.put(:gitlab_issue_id, issue_id)
    |> Map.put_new(:inserted_at, now)
    |> Map.put(:updated_at, now)
  end

  defp normalize_run(issue_id, run_number, attrs, now) do
    attrs = Map.new(attrs)
    status = attrs[:status] || "queued"

    %{
      id: Ecto.UUID.generate(),
      gitlab_issue_id: issue_id,
      run_number: run_number,
      status: if(status in @run_statuses, do: status, else: "queued"),
      mode: attrs[:mode] || "workflow",
      workspace_path: attrs[:workspace_path],
      codex_thread_id: attrs[:codex_thread_id],
      started_at: attrs[:started_at],
      finished_at: attrs[:finished_at],
      last_heartbeat_at: attrs[:last_heartbeat_at],
      exit_reason: attrs[:exit_reason],
      error_message: attrs[:error_message],
      blocked_reason: attrs[:blocked_reason],
      needs_operator_input: attrs[:needs_operator_input] == true,
      summary: attrs[:summary],
      inserted_at: now,
      updated_at: now
    }
  end

  defp put_issue_indexes(state, issue) do
    state
    |> put_in([Access.key(:issue_by_iid), to_string(issue.iid)], issue.id)
    |> put_in([Access.key(:issue_by_gitlab_id), to_string(issue.gitlab_issue_id)], issue.id)
  end

  defp put_issue_order(state, issue_id) do
    if issue_id in state.issue_order do
      state
    else
      %{state | issue_order: state.issue_order ++ [issue_id]}
    end
  end

  defp decorate_issue(state, issue) do
    workflow = Map.get(state.workflow_states, issue.id) || default_workflow_state(issue.id, now())

    issue
    |> Map.put(:identifier, issue_identifier(state, issue))
    |> Map.put(:workflow_state, workflow)
    |> Map.put(:workflow_status, workflow.status)
    |> Map.put(:priority, workflow.priority)
    |> Map.put(:blockers, blocker_dtos(state, issue.id))
    |> Map.put(:blocked_by_count, blocked_by_count(state, issue.id))
    |> Map.put(:active_run_id, active_run_id(state, issue.id))
    |> Map.put(:last_run_status, last_run_status(state, issue.id))
  end

  defp undecorate(issue), do: Map.drop(issue, [:workflow_state, :workflow_status, :priority, :blockers, :blocked_by_count, :active_run_id, :last_run_status])

  defp maybe_decorate_issue(nil, _state), do: nil
  defp maybe_decorate_issue(issue, state), do: decorate_issue(state, issue)

  defp tracker_issue(state, issue) do
    decorated = decorate_issue(state, issue)

    %Issue{
      id: decorated.id,
      identifier: decorated.identifier,
      iid: decorated.iid,
      title: decorated.title,
      description: decorated.description,
      priority: priority_rank(decorated.priority),
      state: decorated.workflow_status,
      workflow_status: decorated.workflow_status,
      gitlab_state: decorated.gitlab_state,
      url: decorated.web_url,
      web_url: decorated.web_url,
      labels: decorated.labels || [],
      assignees: decorated.assignees || [],
      blockers: decorated.blockers || [],
      blocked_by: blocker_refs(state, issue.id),
      notes_summary: notes_summary(state, issue.id),
      created_at: decorated.gitlab_created_at,
      updated_at: decorated.gitlab_updated_at
    }
  end

  defp priority_rank("urgent"), do: 1
  defp priority_rank("high"), do: 2
  defp priority_rank("medium"), do: 3
  defp priority_rank("low"), do: 4
  defp priority_rank(_priority), do: nil

  defp transition(state, issue_id, next_status, opts) do
    next_status = normalize_status(next_status)

    cond do
      next_status not in @workflow_statuses ->
        {:error, :invalid_status}

      not Map.has_key?(state.workflow_states, issue_id) ->
        {:error, :issue_not_found}

      true ->
        workflow = Map.fetch!(state.workflow_states, issue_id)
        previous_status = workflow.status

        if allowed_transition?(previous_status, next_status) do
          now = now()

          workflow =
            workflow
            |> Map.put(:status, next_status)
            |> Map.put(:claimed_by, Keyword.get(opts, :claimed_by, workflow.claimed_by))
            |> Map.put(:claimed_at, Keyword.get(opts, :claimed_at, workflow.claimed_at))
            |> Map.put(:last_transition_at, now)
            |> Map.put(:last_transition_reason, Keyword.get(opts, :reason))
            |> Map.put(:updated_at, now)

          state =
            state
            |> put_in([Access.key(:workflow_states), issue_id], workflow)
            |> append_event("workflow_transitioned", Keyword.get(opts, :source, "local_ui"), %{from: previous_status, to: next_status, reason: Keyword.get(opts, :reason)},
              issue_id: issue_id,
              actor: Keyword.get(opts, :actor, "local_operator")
            )

          {:ok, workflow, state}
        else
          {:error, :invalid_transition}
        end
    end
  end

  defp allowed_transition?(same, same), do: true
  defp allowed_transition?(from, _to) when from in ["done", "canceled"], do: false
  defp allowed_transition?(_from, "canceled"), do: true
  defp allowed_transition?("triage", "todo"), do: true
  defp allowed_transition?("todo", status), do: status in ["in_progress", "blocked"]
  defp allowed_transition?("in_progress", status), do: status in ["blocked", "review", "done", "todo"]
  defp allowed_transition?("blocked", status), do: status in ["todo", "canceled"]
  defp allowed_transition?("review", status), do: status in ["todo", "done"]
  defp allowed_transition?(_from, _to), do: false

  defp blocker_dtos(state, issue_id) do
    state.dependencies
    |> Map.values()
    |> Enum.filter(&(&1.blocked_issue_id == issue_id))
    |> Enum.map(fn edge ->
      blocking_issue = decorate_issue(state, Map.fetch!(state.issues, edge.blocking_issue_id))

      %{
        issue_id: blocking_issue.id,
        iid: blocking_issue.iid,
        identifier: blocking_issue.identifier,
        title: blocking_issue.title,
        status: blocking_issue.workflow_status,
        reason: edge.reason
      }
    end)
  end

  defp blocker_refs(state, issue_id) do
    state.dependencies
    |> Map.values()
    |> Enum.filter(&(&1.blocked_issue_id == issue_id))
    |> Enum.map(fn edge ->
      issue = decorate_issue(state, Map.fetch!(state.issues, edge.blocking_issue_id))
      %{id: issue.id, identifier: issue.identifier, state: issue.workflow_status}
    end)
  end

  defp blocked_by_count(state, issue_id) do
    state.dependencies
    |> Map.values()
    |> Enum.count(&(&1.blocking_issue_id == issue_id))
  end

  defp issue_identifier(state, issue) do
    case Map.get(issue, :identifier) do
      identifier when is_binary(identifier) and identifier != "" ->
        identifier

      _ ->
        case state.project do
          %{path_with_namespace: path} when is_binary(path) and path != "" -> "#{path}##{issue.iid}"
          _ -> "GL-#{issue.iid}"
        end
    end
  end

  defp unresolved_dependency?(state, issue_id) do
    state.dependencies
    |> Map.values()
    |> Enum.filter(&(&1.blocked_issue_id == issue_id))
    |> Enum.any?(fn edge ->
      workflow = Map.get(state.workflow_states, edge.blocking_issue_id, %{})
      workflow.status != "done"
    end)
  end

  defp dependency_path?(state, from_issue_id, target_issue_id) do
    graph =
      state.dependencies
      |> Map.values()
      |> Enum.group_by(& &1.blocked_issue_id, & &1.blocking_issue_id)

    do_dependency_path?(graph, from_issue_id, target_issue_id, MapSet.new())
  end

  defp do_dependency_path?(_graph, issue_id, issue_id, _seen), do: true

  defp do_dependency_path?(graph, issue_id, target_issue_id, seen) do
    if MapSet.member?(seen, issue_id) do
      false
    else
      graph
      |> Map.get(issue_id, [])
      |> Enum.any?(&do_dependency_path?(graph, &1, target_issue_id, MapSet.put(seen, issue_id)))
    end
  end

  defp dependency_key(blocked_issue_id, blocking_issue_id), do: "#{blocked_issue_id}:#{blocking_issue_id}"

  defp labels_satisfy?(issue_labels, required_labels) do
    normalized = MapSet.new(issue_labels || [], &normalize_label/1)
    Enum.all?(required_labels || [], &MapSet.member?(normalized, normalize_label(&1)))
  end

  defp no_active_run?(state, issue_id) do
    state.runs
    |> Map.values()
    |> Enum.reject(&(&1.status in ["succeeded", "failed", "canceled", "stale"]))
    |> Enum.any?(&(&1.gitlab_issue_id == issue_id))
    |> Kernel.not()
  end

  defp active_run_id(state, issue_id) do
    state.runs
    |> Map.values()
    |> Enum.find(fn run ->
      run.gitlab_issue_id == issue_id and run.status in ["queued", "starting", "running", "blocked"]
    end)
    |> case do
      nil -> nil
      run -> run.id
    end
  end

  defp last_run_status(state, issue_id) do
    state.run_order
    |> Enum.reverse()
    |> Enum.map(&Map.get(state.runs, &1))
    |> Enum.find(&(&1 && &1.gitlab_issue_id == issue_id))
    |> case do
      nil -> nil
      run -> run.status
    end
  end

  defp next_run_number(state, issue_id) do
    state.runs
    |> Map.values()
    |> Enum.filter(&(&1.gitlab_issue_id == issue_id))
    |> Enum.map(& &1.run_number)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  defp decorate_run(state, run) do
    issue = Map.get(state.issues, run.gitlab_issue_id)

    run
    |> Map.put(:issue, issue && decorate_issue(state, issue))
    |> Map.put(:issue_identifier, issue && issue_identifier(state, issue))
    |> Map.put(:issue_title, issue && issue.title)
    |> Map.put(:issue_web_url, issue && issue.web_url)
  end

  defp maybe_decorate_run(nil, _state), do: nil
  defp maybe_decorate_run(run, state), do: decorate_run(state, run)

  defp decorate_block(state, block) do
    issue = Map.get(state.issues, block.gitlab_issue_id)

    block
    |> Map.put(:issue, issue && decorate_issue(state, issue))
    |> Map.put(:issue_identifier, issue && issue_identifier(state, issue))
    |> Map.put(:issue_title, issue && issue.title)
    |> Map.put(:issue_web_url, issue && issue.web_url)
  end

  defp append_event(state, event_type, source, payload, opts) when source in @event_sources do
    event = %{
      id: Ecto.UUID.generate(),
      gitlab_issue_id: Keyword.get(opts, :issue_id),
      event_type: event_type,
      source: source,
      actor: Keyword.get(opts, :actor),
      payload: payload || %{},
      run_id: Keyword.get(opts, :run_id),
      inserted_at: now()
    }

    %{state | events: [event | Enum.take(state.events, 499)]}
  end

  defp append_event(state, event_type, _source, payload, opts), do: append_event(state, event_type, "system", payload, opts)

  defp to_snapshot(state) do
    %{
      project: state.project,
      issues: Enum.map(state.issue_order, &(state.issues |> Map.get(&1) |> maybe_decorate_issue(state))) |> Enum.reject(&is_nil/1),
      cursors: state.cursors,
      runs: Enum.map(state.run_order, &(state.runs |> Map.get(&1) |> maybe_decorate_run(state))) |> Enum.reject(&is_nil/1),
      runtime_blocks: state.runtime_blocks |> Map.values() |> Enum.map(&decorate_block(state, &1)),
      open_runtime_blocks: state.runtime_blocks |> Map.values() |> Enum.reject(& &1.resolved_at) |> Enum.map(&decorate_block(state, &1)),
      events: state.events,
      started_at: state.started_at
    }
  end

  defp apply_issue_filters(issues, filters) do
    Enum.filter(issues, fn issue ->
      Enum.all?(filters, fn
        {:status, status} -> issue.workflow_status == status
        {:gitlab_state, state} -> issue.gitlab_state == state
        {:search, search} -> issue_matches_search?(issue, search)
        _ -> true
      end)
    end)
  end

  defp issue_matches_search?(_issue, search) when search in [nil, ""], do: true

  defp issue_matches_search?(issue, search) do
    haystack = Enum.join([Map.get(issue, :identifier), issue.title, issue.description_preview], " ") |> String.downcase()
    String.contains?(haystack, String.downcase(search))
  end

  defp apply_event_filters(events, filters) do
    events
    |> Enum.filter(fn event ->
      Enum.all?(filters, fn
        {:issue_id, issue_id} -> event.gitlab_issue_id == issue_id
        {:run_id, run_id} -> event.run_id == run_id
        _ -> true
      end)
    end)
  end

  defp apply_run_filters(runs, filters) do
    Enum.filter(runs, fn run ->
      Enum.all?(filters, fn
        {:issue_id, issue_id} -> run.gitlab_issue_id == issue_id
        _ -> true
      end)
    end)
  end

  defp sort_notes(notes), do: Enum.sort_by(notes, &(&1.gitlab_created_at || &1.inserted_at), DateTime)

  defp notes_summary(state, issue_id) do
    case Map.get(state.notes, issue_id, []) do
      [] -> nil
      notes -> notes |> Enum.take(-3) |> Enum.map(& &1.body) |> Enum.join("\n\n")
    end
  end

  defp normalize_label(label) when is_binary(label), do: label |> String.trim() |> String.downcase()
  defp normalize_label(label), do: label |> to_string() |> normalize_label()

  defp normalize_status(status) when is_binary(status), do: status |> String.trim() |> String.downcase()
  defp normalize_status(status), do: to_string(status)

  defp normalize_priority(priority) when is_binary(priority), do: priority |> String.trim() |> String.downcase()
  defp normalize_priority(priority), do: to_string(priority)

  defp cursor_key(source, cursor_name), do: "#{source}:#{cursor_name}"

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp hydrate_issue(issue) do
    hydrate_datetime_fields(issue, [
      :gitlab_created_at,
      :gitlab_updated_at,
      :closed_at,
      :last_synced_at,
      :inserted_at,
      :updated_at
    ])
    |> hydrate_date_fields([:due_date])
  end

  defp hydrate_datetime_fields(map, fields) when is_map(map) do
    Enum.reduce(fields, map, fn field, acc ->
      case Map.get(acc, field) do
        value when is_binary(value) ->
          case DateTime.from_iso8601(value) do
            {:ok, datetime, _} -> Map.put(acc, field, datetime)
            _ -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp hydrate_date_fields(map, fields) when is_map(map) do
    Enum.reduce(fields, map, fn field, acc ->
      case Map.get(acc, field) do
        value when is_binary(value) ->
          case Date.from_iso8601(value) do
            {:ok, date} -> Map.put(acc, field, date)
            _ -> acc
          end

        _ ->
          acc
      end
    end)
  end

  defp update_map_values(map, key, fun) do
    Map.update(map, key, %{}, fn values ->
      Map.new(values || %{}, fn {k, v} -> {to_string(k), fun.(v)} end)
    end)
  end

  defp update_notes(map) do
    Map.update(map, :notes, %{}, fn values ->
      Map.new(values || %{}, fn {k, notes} ->
        {to_string(k), Enum.map(notes || [], &hydrate_datetime_fields(&1, [:gitlab_created_at, :gitlab_updated_at, :inserted_at, :updated_at]))}
      end)
    end)
  end

  defp update_events(map) do
    Map.update(map, :events, [], fn events ->
      Enum.map(events || [], &hydrate_datetime_fields(&1, [:inserted_at]))
    end)
  end

  defp update_run_events(map) do
    Map.update(map, :run_events, %{}, fn values ->
      Map.new(values || %{}, fn {k, events} ->
        {to_string(k), Enum.map(events || [], &hydrate_datetime_fields(&1, [:inserted_at]))}
      end)
    end)
  end
end
