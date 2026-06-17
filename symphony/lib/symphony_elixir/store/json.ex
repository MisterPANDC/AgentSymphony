defmodule SymphonyElixir.Store.Json do
  @moduledoc """
  Explicit local JSON state for GitLab-backed Symphony.

  PostgreSQL is the default and conforming persistence backend. This module is
  retained only for tests and one-off local tooling that explicitly opt in.
  """

  use GenServer

  alias SymphonyElixir.Tracker.Issue
  alias SymphonyElixir.Workflow.Transitions

  @workflow_statuses Transitions.statuses()
  @priorities ~w(none low medium high urgent)
  @run_statuses ~w(queued starting running blocked succeeded failed canceled stale)
  @block_types ~w(operator_input approval_required mcp_elicitation sandbox_rejection external_failure blocked_by_dependency)
  @event_sources ~w(gitlab_sync user_ui agent system)
  @relation_types ~w(relates_to)
  @credential_modes ~w(project_access_token service_account)
  @registered_agent_providers ~w(codex)
  @registered_agent_auth_modes ~w(subscription api auth_json)
  @registered_agent_credential_statuses ~w(pending login_started configured failed)
  @registered_agent_mcp_install_statuses ~w(pending installing configured failed)
  @registered_agent_usage_statuses ~w(unknown available unavailable not_applicable)

  defstruct [
    :path,
    :started_at,
    :project,
    projects: %{},
    identities: %{},
    oauth_tokens: %{},
    service_account_credentials: %{},
    project_memberships: %{},
    registered_agents: %{},
    registered_agent_order: [],
    issues: %{},
    issue_order: [],
    issue_by_iid: %{},
    issue_by_gitlab_id: %{},
    workflow_states: %{},
    dependencies: %{},
    relations: %{},
    notes: %{},
    merge_requests: %{},
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
    with path when is_binary(path) <- Keyword.get(opts, :path) || Application.get_env(:symphony_elixir, :store_path) do
      path = Path.expand(path)
      File.mkdir_p!(Path.dirname(path))

      state =
        path
        |> load_state()
        |> Map.put(:path, path)
        |> Map.put_new(:started_at, DateTime.utc_now())
        |> struct_state()

      {:ok, state}
    else
      _ -> {:stop, :json_store_path_required}
    end
  end

  @spec upsert_project(map()) :: map()
  def upsert_project(attrs), do: call({:upsert_project, attrs})

  @spec project() :: map() | nil
  def project, do: call(:project)

  @spec projects() :: [map()]
  def projects, do: call(:projects)

  @spec project_by_id(String.t()) :: map() | nil
  def project_by_id(id), do: call({:project_by_id, id})

  @spec upsert_gitlab_identity(map()) :: map()
  def upsert_gitlab_identity(attrs), do: call({:upsert_gitlab_identity, attrs})

  @spec upsert_oauth_token(String.t(), map()) :: map()
  def upsert_oauth_token(identity_id, attrs), do: call({:upsert_oauth_token, identity_id, attrs})

  @spec oauth_token(String.t()) :: map() | nil
  def oauth_token(identity_id), do: call({:oauth_token, identity_id})

  @spec upsert_project_membership(String.t(), String.t(), map()) :: map()
  def upsert_project_membership(identity_id, project_setting_id, attrs),
    do: call({:upsert_project_membership, identity_id, project_setting_id, attrs})

  @spec put_project_access_token(String.t(), String.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def put_project_access_token(project_setting_id, token, identity_id \\ nil),
    do: call({:put_project_access_token, project_setting_id, token, identity_id})

  @spec project_access_token(map() | String.t()) :: {:ok, String.t()} | {:error, term()}
  def project_access_token(project_or_id), do: call({:project_access_token, project_or_id})

  @spec put_project_automation_credential_mode(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def put_project_automation_credential_mode(project_setting_id, mode),
    do: call({:put_project_automation_credential_mode, project_setting_id, mode})

  @spec put_service_account_token(String.t(), String.t(), String.t() | nil, map()) :: {:ok, map()} | {:error, term()}
  def put_service_account_token(api_root, token, identity_id \\ nil, attrs \\ %{}),
    do: call({:put_service_account_token, api_root, token, identity_id, attrs})

  @spec service_account_credential(String.t()) :: map() | nil
  def service_account_credential(api_root), do: call({:service_account_credential, api_root})

  @spec service_account_token(String.t()) :: {:ok, String.t()} | {:error, term()}
  def service_account_token(api_root), do: call({:service_account_token, api_root})

  @spec automation_credential(map() | String.t()) :: {:ok, map()} | {:error, term()}
  def automation_credential(project_or_id), do: call({:automation_credential, project_or_id})

  @spec put_project_local_repo_path(String.t(), String.t() | nil) :: {:ok, map()} | {:error, term()}
  def put_project_local_repo_path(project_setting_id, local_repo_path),
    do: call({:put_project_local_repo_path, project_setting_id, local_repo_path})

  @spec list_registered_agents() :: [map()]
  def list_registered_agents, do: call(:list_registered_agents)

  @spec create_registered_agent(map()) :: {:ok, map()} | {:error, term()}
  def create_registered_agent(attrs), do: call({:create_registered_agent, attrs})

  @spec update_registered_agent(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_registered_agent(agent_id, attrs), do: call({:update_registered_agent, agent_id, attrs})

  @spec upsert_issue(map()) :: map()
  def upsert_issue(attrs), do: call({:upsert_issue, attrs})

  @spec backfill_issue_project_setting(map()) :: non_neg_integer()
  def backfill_issue_project_setting(project), do: call({:backfill_issue_project_setting, project})

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

  @spec list_candidate_tracker_issues([String.t()], [String.t()]) :: [Issue.t()]
  def list_candidate_tracker_issues(required_labels, active_states),
    do: call({:list_candidate_tracker_issues, required_labels, active_states})

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

  @spec list_issue_relations(String.t()) :: map()
  def list_issue_relations(issue_id), do: call({:list_issue_relations, issue_id})

  @spec add_issue_relation(String.t(), String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def add_issue_relation(source_issue_id, target_issue_id, relation_type, opts \\ []),
    do: call({:add_issue_relation, source_issue_id, target_issue_id, relation_type, opts})

  @spec upsert_note(String.t(), map()) :: map()
  def upsert_note(issue_id, attrs), do: call({:upsert_note, issue_id, attrs})

  @spec list_notes(String.t()) :: [map()]
  def list_notes(issue_id), do: call({:list_notes, issue_id})

  @spec delete_note(String.t(), integer() | String.t()) :: :ok | {:error, term()}
  def delete_note(issue_id, note_id), do: call({:delete_note, issue_id, note_id})

  @spec replace_project_merge_requests(String.t(), [map()]) :: [map()]
  def replace_project_merge_requests(project_setting_id, entries), do: call({:replace_project_merge_requests, project_setting_id, entries})

  @spec upsert_merge_request(String.t(), String.t(), map()) :: map()
  def upsert_merge_request(project_setting_id, issue_id, attrs), do: call({:upsert_merge_request, project_setting_id, issue_id, attrs})

  @spec list_merge_requests(String.t()) :: [map()]
  def list_merge_requests(issue_id), do: call({:list_merge_requests, issue_id})

  @spec merge_request_counts([String.t()]) :: map()
  def merge_request_counts(issue_ids), do: call({:merge_request_counts, issue_ids})

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
    existing = find_project(state.projects, attrs)
    project = normalize_project(attrs, existing, now)
    projects = Map.put(state.projects, project.id, project)
    state = persist(%{state | project: project, projects: projects})
    {:reply, public_project(project, state), state}
  end

  def handle_call(:project, _from, state), do: {:reply, state.project && public_project(state.project, state), state}

  def handle_call(:projects, _from, state) do
    projects =
      state.projects
      |> Map.values()
      |> Enum.map(&public_project(&1, state))

    {:reply, projects, state}
  end

  def handle_call({:project_by_id, id}, _from, state) do
    project =
      state.projects
      |> Map.get(id)
      |> case do
        nil -> if state.project && state.project.id == id, do: state.project
        project -> project
      end

    {:reply, project && public_project(project, state), state}
  end

  def handle_call({:upsert_gitlab_identity, attrs}, _from, state) do
    now = now()
    identity = normalize_identity(attrs, now)
    state = state |> put_in([Access.key(:identities), identity_key(identity)], identity) |> persist()
    {:reply, identity, state}
  end

  def handle_call({:upsert_oauth_token, identity_id, attrs}, _from, state) do
    now = now()

    with {:ok, encrypted_access_token} <- SymphonyElixir.Auth.TokenVault.seal(attrs["access_token"] || attrs[:access_token]),
         {:ok, encrypted_refresh_token} <- SymphonyElixir.Auth.TokenVault.seal(attrs["refresh_token"] || attrs[:refresh_token]) do
      existing = Map.get(state.oauth_tokens, identity_id, %{})

      token =
        existing
        |> Map.merge(%{
          id: existing[:id] || Ecto.UUID.generate(),
          identity_id: identity_id,
          encrypted_access_token: encrypted_access_token,
          encrypted_refresh_token: encrypted_refresh_token || existing[:encrypted_refresh_token],
          scopes: oauth_scopes(attrs),
          token_type: attrs["token_type"] || attrs[:token_type],
          expires_at: oauth_expires_at(attrs, now),
          last_refreshed_at: now,
          inserted_at: existing[:inserted_at] || now,
          updated_at: now
        })

      state = state |> put_in([Access.key(:oauth_tokens), identity_id], token) |> persist()
      {:reply, token, state}
    else
      {:error, reason} -> raise "failed to seal OAuth token: #{inspect(reason)}"
    end
  end

  def handle_call({:oauth_token, identity_id}, _from, state), do: {:reply, Map.get(state.oauth_tokens, identity_id), state}

  def handle_call({:upsert_project_membership, identity_id, project_setting_id, attrs}, _from, state) do
    now = now()
    membership = normalize_project_membership(identity_id, project_setting_id, attrs, now)
    state = state |> put_in([Access.key(:project_memberships), membership_key(identity_id, project_setting_id)], membership) |> persist()
    {:reply, membership, state}
  end

  def handle_call({:put_project_access_token, project_setting_id, token, identity_id}, _from, state) do
    case Map.get(state.projects, project_setting_id) || (state.project && state.project.id == project_setting_id && state.project) do
      %{id: ^project_setting_id} = project ->
        case SymphonyElixir.Auth.TokenVault.seal(token) do
          {:ok, encrypted} ->
            project =
              project
              |> Map.put(:encrypted_project_access_token, encrypted)
              |> Map.put(:project_access_token_set_by_identity_id, identity_id)
              |> Map.put(:project_access_token_set_at, now())
              |> Map.put(:updated_at, now())

            projects = Map.put(state.projects, project.id, project)
            current_project = if state.project && state.project.id == project.id, do: project, else: state.project
            state = persist(%{state | project: current_project, projects: projects})
            {:reply, {:ok, public_project(project, state)}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      _ ->
        {:reply, {:error, :project_not_found}, state}
    end
  end

  def handle_call({:project_access_token, project_or_id}, _from, state) do
    project =
      case project_or_id do
        id when is_binary(id) ->
          Map.get(state.projects, id) || if state.project && state.project.id == id, do: state.project

        %{encrypted_project_access_token: _} = project ->
          project

        _ ->
          nil
      end

    reply =
      case project do
        %{encrypted_project_access_token: encrypted} when is_binary(encrypted) ->
          SymphonyElixir.Auth.TokenVault.open(encrypted)

        _ ->
          {:error, :project_access_token_missing}
      end

    {:reply, reply, state}
  end

  def handle_call({:put_project_automation_credential_mode, project_setting_id, mode}, _from, state) when mode in @credential_modes do
    case Map.get(state.projects, project_setting_id) || (state.project && state.project.id == project_setting_id && state.project) do
      %{id: ^project_setting_id} = project ->
        project =
          project
          |> Map.put(:automation_credential_mode, mode)
          |> Map.put(:updated_at, now())

        projects = Map.put(state.projects, project.id, project)
        current_project = if state.project && state.project.id == project.id, do: project, else: state.project
        state = persist(%{state | project: current_project, projects: projects})
        {:reply, {:ok, public_project(project, state)}, state}

      _ ->
        {:reply, {:error, :project_not_found}, state}
    end
  end

  def handle_call({:put_project_automation_credential_mode, _project_setting_id, _mode}, _from, state) do
    {:reply, {:error, :invalid_automation_credential_mode}, state}
  end

  def handle_call({:put_project_local_repo_path, project_setting_id, local_repo_path}, _from, state) do
    case Map.get(state.projects, project_setting_id) || (state.project && state.project.id == project_setting_id && state.project) do
      %{id: ^project_setting_id} = project ->
        project =
          project
          |> Map.put(:local_repo_path, normalize_blank(local_repo_path))
          |> Map.put(:updated_at, now())

        projects = Map.put(state.projects, project.id, project)
        current_project = if state.project && state.project.id == project.id, do: project, else: state.project
        state = persist(%{state | project: current_project, projects: projects})
        {:reply, {:ok, public_project(project, state)}, state}

      _ ->
        {:reply, {:error, :project_not_found}, state}
    end
  end

  def handle_call({:put_service_account_token, api_root, token, identity_id, attrs}, _from, state)
      when is_binary(api_root) and is_binary(token) do
    case SymphonyElixir.Auth.TokenVault.seal(token) do
      {:ok, encrypted} ->
        existing = Map.get(state.service_account_credentials, api_root, %{})

        credential =
          existing
          |> Map.merge(normalize_service_account_attrs(attrs))
          |> Map.merge(%{
            id: existing[:id] || Ecto.UUID.generate(),
            api_root: api_root,
            encrypted_service_account_token: encrypted,
            service_account_token_set_by_identity_id: identity_id,
            service_account_token_set_at: now(),
            last_validated_at: now(),
            last_validation_error: nil,
            inserted_at: existing[:inserted_at] || now(),
            updated_at: now()
          })

        state =
          state
          |> put_in([Access.key(:service_account_credentials), api_root], credential)
          |> persist()

        {:reply, {:ok, public_service_account_credential(credential)}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:put_service_account_token, _api_root, _token, _identity_id, _attrs}, _from, state) do
    {:reply, {:error, :missing_service_account_token}, state}
  end

  def handle_call({:service_account_credential, api_root}, _from, state) do
    credential = if is_binary(api_root), do: Map.get(state.service_account_credentials, api_root)
    {:reply, credential && public_service_account_credential(credential), state}
  end

  def handle_call({:service_account_token, api_root}, _from, state) do
    reply =
      case if(is_binary(api_root), do: Map.get(state.service_account_credentials, api_root)) do
        %{encrypted_service_account_token: encrypted} when is_binary(encrypted) ->
          open_encrypted_token(encrypted, :service_account_token_missing)

        _ ->
          {:error, :service_account_token_missing}
      end

    {:reply, reply, state}
  end

  def handle_call({:automation_credential, project_or_id}, _from, state) do
    project = resolve_project(state, project_or_id)

    reply =
      case project do
        nil ->
          {:error, :project_not_found}

        %{automation_credential_mode: "service_account", api_root: api_root, id: project_id} ->
          case Map.get(state.service_account_credentials, api_root) do
            %{encrypted_service_account_token: encrypted} when is_binary(encrypted) ->
              with {:ok, token} <- open_encrypted_token(encrypted, :service_account_token_missing) do
                {:ok, %{mode: "service_account", token: token, api_root: api_root, project_setting_id: project_id}}
              end

            _ ->
              {:error, :service_account_token_missing}
          end

        %{encrypted_project_access_token: encrypted, api_root: api_root, id: project_id} when is_binary(encrypted) ->
          with {:ok, token} <- open_encrypted_token(encrypted, :project_access_token_missing) do
            {:ok, %{mode: "project_access_token", token: token, api_root: api_root, project_setting_id: project_id}}
          end

        _ ->
          {:error, :project_access_token_missing}
      end

    {:reply, reply, state}
  end

  def handle_call(:list_registered_agents, _from, state) do
    agents =
      state.registered_agent_order
      |> Enum.map(&Map.get(state.registered_agents, &1))
      |> Enum.reject(&is_nil/1)

    {:reply, agents, state}
  end

  def handle_call({:create_registered_agent, attrs}, _from, state) do
    now = now()

    case normalize_registered_agent(attrs, now) do
      {:ok, agent} ->
        if Enum.any?(Map.values(state.registered_agents), &(&1.codex_home == agent.codex_home)) do
          {:reply, {:error, :codex_home_taken}, state}
        else
          state =
            state
            |> put_in([Access.key(:registered_agents), agent.id], agent)
            |> update_in([Access.key(:registered_agent_order)], &(&1 ++ [agent.id]))
            |> persist()

          {:reply, {:ok, agent}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:update_registered_agent, agent_id, attrs}, _from, state) do
    case Map.get(state.registered_agents, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_found}, state}

      agent ->
        attrs = Map.new(attrs)

        updated =
          agent
          |> Map.merge(%{
            credential_status: attrs[:credential_status] || attrs["credential_status"] || agent.credential_status,
            login_started_at: attrs[:login_started_at] || attrs["login_started_at"] || agent.login_started_at,
            last_login_exit_status: attrs[:last_login_exit_status] || attrs["last_login_exit_status"],
            last_login_message: attrs[:last_login_message] || attrs["last_login_message"],
            mcp_install_status: map_value(attrs, :mcp_install_status, agent[:mcp_install_status] || "pending"),
            mcp_install_started_at: map_value(attrs, :mcp_install_started_at, agent[:mcp_install_started_at]),
            mcp_install_finished_at: map_value(attrs, :mcp_install_finished_at, agent[:mcp_install_finished_at]),
            mcp_install_exit_status: map_value(attrs, :mcp_install_exit_status, agent[:mcp_install_exit_status]),
            mcp_install_message: map_value(attrs, :mcp_install_message, agent[:mcp_install_message]),
            mcp_server_names: map_value(attrs, :mcp_server_names, agent[:mcp_server_names] || []),
            usage_status: map_value(attrs, :usage_status, agent[:usage_status] || "unknown"),
            usage_snapshot: map_value(attrs, :usage_snapshot, agent[:usage_snapshot]),
            usage_checked_at: map_value(attrs, :usage_checked_at, agent[:usage_checked_at]),
            usage_error: map_value(attrs, :usage_error, agent[:usage_error]),
            updated_at: now()
          })

        if updated.credential_status in @registered_agent_credential_statuses and
             updated.mcp_install_status in @registered_agent_mcp_install_statuses and
             updated.usage_status in @registered_agent_usage_statuses do
          state = put_in(state.registered_agents[agent_id], updated) |> persist()
          {:reply, {:ok, updated}, state}
        else
          {:reply, {:error, :invalid_registered_agent_status}, state}
        end
    end
  end

  def handle_call({:upsert_issue, attrs}, _from, state) do
    now = now()
    local_id = issue_local_id(attrs)
    existing = Map.get(state.issues, local_id, %{})
    project = project_for_issue_attrs(state, attrs)
    issue = normalize_issue(attrs, existing, now, project)
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

  def handle_call({:backfill_issue_project_setting, project}, _from, state) do
    {state, count} = backfill_issue_project_setting(state, project)
    state = if count > 0, do: persist(state), else: state
    {:reply, count, state}
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

  def handle_call({:list_candidate_tracker_issues, required_labels, active_states}, _from, state) do
    active_statuses = MapSet.new(active_states || [], &normalize_status/1)

    issues =
      state.issue_order
      |> Enum.map(&Map.get(state.issues, &1))
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn issue ->
        workflow = Map.get(state.workflow_states, issue.id, %{})

        issue.gitlab_state == "opened" and MapSet.member?(active_statuses, workflow.status) and
          not unresolved_dependency?(state, issue.id) and open_runtime_block_count(state, issue.id) == 0 and
          labels_satisfy?(issue.labels, required_labels) and
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
          |> append_event("workflow_priority_changed", "user_ui", %{priority: priority}, issue_id: issue_id)
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
            created_by: Keyword.get(opts, :actor, "system"),
            reason: Keyword.get(opts, :reason),
            inserted_at: now(),
            updated_at: now()
          }

          state =
            state
            |> put_in([Access.key(:dependencies), dependency_key(blocked_issue_id, blocking_issue_id)], edge)
            |> append_event(
              "dependency_added",
              Keyword.get(opts, :source, "user_ui"),
              Map.take(edge, [:blocking_issue_id, :reason]),
              issue_id: blocked_issue_id,
              actor: Keyword.get(opts, :actor, "system")
            )
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
        |> append_event("dependency_removed", "user_ui", %{blocking_issue_id: blocking_issue_id}, issue_id: blocked_issue_id)
        |> persist()

      {:reply, :ok, state}
    else
      {:reply, {:error, :dependency_not_found}, state}
    end
  end

  def handle_call({:list_issue_relations, issue_id}, _from, state) do
    {:reply, relation_dtos(state, issue_id), state}
  end

  def handle_call({:add_issue_relation, source_issue_id, target_issue_id, relation_type, opts}, _from, state) do
    relation_type = normalize_relation_type(relation_type)

    result =
      cond do
        relation_type not in @relation_types ->
          {:error, :invalid_relation_type}

        source_issue_id == target_issue_id ->
          {:error, :self_relation}

        not Map.has_key?(state.issues, source_issue_id) or not Map.has_key?(state.issues, target_issue_id) ->
          {:error, :issue_not_found}

        true ->
          now = now()

          relation = %{
            id: Ecto.UUID.generate(),
            source_issue_id: source_issue_id,
            target_issue_id: target_issue_id,
            relation_type: relation_type,
            created_by: Keyword.get(opts, :actor, "system"),
            reason: Keyword.get(opts, :reason),
            metadata: Keyword.get(opts, :metadata, %{}) || %{},
            inserted_at: now,
            updated_at: now
          }

          key = relation_key(source_issue_id, target_issue_id, relation_type)

          state =
            state
            |> put_in([Access.key(:relations), key], relation)
            |> append_event(
              "issue_relation_added",
              Keyword.get(opts, :source, "user_ui"),
              Map.take(relation, [:target_issue_id, :relation_type, :reason, :metadata]),
              issue_id: source_issue_id,
              actor: Keyword.get(opts, :actor, "system")
            )
            |> persist()

          {:ok, relation, state}
      end

    case result do
      {:ok, relation, state} -> {:reply, {:ok, relation}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
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

  def handle_call({:delete_note, issue_id, note_id}, _from, state) do
    parsed_note_id = parse_int(note_id)

    if is_nil(parsed_note_id) do
      {:reply, {:error, :invalid_note_id}, state}
    else
      notes = state.notes |> Map.get(issue_id, []) |> Enum.reject(&(&1.note_id == parsed_note_id))

      state =
        state
        |> put_in([Access.key(:notes), issue_id], notes)
        |> append_event("gitlab_note_deleted", "gitlab_sync", %{note_id: parsed_note_id}, issue_id: issue_id)
        |> persist()

      {:reply, :ok, state}
    end
  end

  def handle_call({:replace_project_merge_requests, project_setting_id, entries}, _from, state) do
    project_issue_ids =
      state.issues
      |> Map.values()
      |> Enum.filter(&(&1.gitlab_project_setting_id == project_setting_id))
      |> MapSet.new(& &1.id)

    merge_requests =
      state.merge_requests
      |> Map.drop(MapSet.to_list(project_issue_ids))

    synced =
      entries
      |> Enum.map(&normalize_merge_request(project_setting_id, &1, now()))
      |> Enum.reject(&is_nil/1)
      |> Enum.group_by(& &1.gitlab_issue_id)

    state =
      state
      |> Map.put(:merge_requests, Map.merge(merge_requests, synced))
      |> persist()

    {:reply, synced |> Map.values() |> List.flatten(), state}
  end

  def handle_call({:upsert_merge_request, project_setting_id, issue_id, attrs}, _from, state) do
    merge_request = normalize_merge_request(project_setting_id, %{issue_id: issue_id, attrs: attrs}, now())

    if is_nil(merge_request) do
      {:reply, nil, state}
    else
      merge_request_id = merge_request[:merge_request_id] || merge_request["merge_request_id"]

      merge_requests =
        state.merge_requests
        |> Map.get(issue_id, [])
        |> Enum.reject(&((&1[:merge_request_id] || &1["merge_request_id"]) == merge_request_id))

      state =
        state
        |> Map.put(:merge_requests, Map.put(state.merge_requests, issue_id, sort_merge_requests([merge_request | merge_requests])))
        |> persist()

      {:reply, merge_request, state}
    end
  end

  def handle_call({:list_merge_requests, issue_id}, _from, state) do
    merge_requests =
      state.merge_requests
      |> Map.get(issue_id, [])
      |> sort_merge_requests()

    {:reply, merge_requests, state}
  end

  def handle_call({:merge_request_counts, issue_ids}, _from, state) do
    wanted = MapSet.new(issue_ids || [])

    counts =
      state.merge_requests
      |> Enum.filter(fn {issue_id, _merge_requests} -> MapSet.member?(wanted, issue_id) end)
      |> Map.new(fn {issue_id, merge_requests} -> {issue_id, length(merge_requests)} end)

    {:reply, counts, state}
  end

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
          |> append_event("runtime_block_resolved", "user_ui", %{block_id: block.id}, issue_id: block.gitlab_issue_id, run_id: block.agent_run_id)
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
    |> update_map_values(:identities, &hydrate_datetime_fields(&1, [:last_login_at, :inserted_at, :updated_at]))
    |> update_map_values(:oauth_tokens, &hydrate_datetime_fields(&1, [:expires_at, :last_refreshed_at, :inserted_at, :updated_at]))
    |> update_map_values(:service_account_credentials, &hydrate_service_account_credential/1)
    |> update_map_values(:projects, &hydrate_project/1)
    |> update_map_values(:project_memberships, &hydrate_datetime_fields(&1, [:expires_at, :last_checked_at, :inserted_at, :updated_at]))
    |> update_map_values(
      :registered_agents,
      &hydrate_datetime_fields(&1, [
        :login_started_at,
        :mcp_install_started_at,
        :mcp_install_finished_at,
        :usage_checked_at,
        :inserted_at,
        :updated_at
      ])
    )
    |> update_map_values(:issues, &hydrate_issue/1)
    |> update_map_values(:workflow_states, &hydrate_workflow_state/1)
    |> update_map_values(:dependencies, &hydrate_datetime_fields(&1, [:inserted_at, :updated_at]))
    |> update_map_values(:relations, &hydrate_datetime_fields(&1, [:inserted_at, :updated_at]))
    |> update_map_values(:runs, &hydrate_datetime_fields(&1, [:started_at, :finished_at, :last_heartbeat_at, :inserted_at, :updated_at]))
    |> update_map_values(:runtime_blocks, &hydrate_datetime_fields(&1, [:resolved_at, :inserted_at, :updated_at]))
    |> update_map_values(:cursors, &hydrate_datetime_fields(&1, [:last_success_at, :last_attempt_at, :last_error_at, :inserted_at, :updated_at]))
    |> update_notes()
    |> update_events()
    |> update_run_events()
  end

  defp struct_state(map) do
    state = struct(__MODULE__, Map.merge(%__MODULE__{} |> Map.from_struct(), map))
    projects = migrate_projects(state.project, state.projects)
    project = current_project(state.project, projects)
    %{state | project: project, projects: projects}
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
    |> Map.put_new(:automation_credential_mode, "project_access_token")
    |> Map.put(:updated_at, now)
    |> Map.put_new(:inserted_at, now)
  end

  defp find_project(projects, attrs) do
    attrs = Map.new(attrs)
    api_root = attrs[:api_root] || attrs["api_root"]
    project_id = attrs[:project_id] || attrs["project_id"]
    project_ref = attrs[:project_ref] || attrs["project_ref"]

    Enum.find(Map.values(projects), fn project ->
      same_api_root? = is_nil(api_root) or (is_binary(api_root) and project[:api_root] == api_root)

      cond do
        same_api_root? and not is_nil(project_id) ->
          to_string(project[:project_id]) == to_string(project_id)

        same_api_root? and is_binary(project_ref) ->
          project[:project_ref] == project_ref

        true ->
          false
      end
    end)
  end

  defp migrate_projects(_project, projects) when is_map(projects) and map_size(projects) > 0 do
    Map.new(projects, fn {id, value} ->
      project = Map.put_new(value, :id, to_string(id))
      {project.id, project}
    end)
  end

  defp migrate_projects(%{id: id} = project, _projects) when is_binary(id), do: %{id => project}
  defp migrate_projects(_project, _projects), do: %{}

  defp current_project(%{id: id}, projects) when is_binary(id), do: Map.get(projects, id)
  defp current_project(_project, projects), do: projects |> Map.values() |> List.first()

  defp hydrate_project(project) do
    project
    |> hydrate_datetime_fields([:last_validated_at, :project_access_token_set_at, :inserted_at, :updated_at])
    |> Map.put_new(:automation_credential_mode, "project_access_token")
  end

  defp hydrate_service_account_credential(credential) do
    hydrate_datetime_fields(credential, [:service_account_token_set_at, :last_validated_at, :inserted_at, :updated_at])
  end

  defp public_project(project, state) when is_map(project) do
    mode = credential_mode(project)
    project_token_status = token_status(project[:encrypted_project_access_token])
    service_status = project |> service_account_for_project(state) |> service_account_token_status()

    project
    |> Map.drop([:encrypted_project_access_token, :project_access_token_set_by_identity_id])
    |> Map.put(:automation_credential_mode, mode)
    |> Map.put_new(:local_repo_path, nil)
    |> Map.put(:project_access_token_status, project_token_status)
    |> Map.put(:service_account_token_status, service_status)
    |> Map.put(:automation_credential_status, automation_credential_status(mode, project_token_status, service_status))
  end

  defp token_status(value) when is_binary(value) and value != "", do: "configured"
  defp token_status(_value), do: "missing"

  defp public_service_account_credential(credential) when is_map(credential) do
    credential
    |> Map.drop([:encrypted_service_account_token, :service_account_token_set_by_identity_id])
    |> Map.put(:service_account_token_status, token_status(credential[:encrypted_service_account_token]))
  end

  defp service_account_for_project(%{api_root: api_root}, %__MODULE__{} = state) when is_binary(api_root),
    do: Map.get(state.service_account_credentials, api_root)

  defp service_account_for_project(_project, _state), do: nil

  defp service_account_token_status(%{encrypted_service_account_token: encrypted}), do: token_status(encrypted)
  defp service_account_token_status(_credential), do: "missing"

  defp automation_credential_status("service_account", _project_status, service_status), do: service_status
  defp automation_credential_status(_mode, project_status, _service_status), do: project_status

  defp credential_mode(%{automation_credential_mode: mode}) when mode in @credential_modes, do: mode
  defp credential_mode(_project), do: "project_access_token"

  defp open_encrypted_token(encrypted, missing_reason) do
    case SymphonyElixir.Auth.TokenVault.open(encrypted) do
      {:ok, token} when is_binary(token) and token != "" -> {:ok, token}
      {:ok, _} -> {:error, missing_reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_project(%__MODULE__{} = state, id) when is_binary(id),
    do: Map.get(state.projects, id) || if(state.project && state.project.id == id, do: state.project)

  defp resolve_project(_state, %{id: id} = project) when is_binary(id) do
    if Map.has_key?(project, :encrypted_project_access_token) or Map.has_key?(project, :automation_credential_mode) do
      project
    end
  end

  defp resolve_project(_state, _project_or_id), do: nil

  defp normalize_blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_blank(_value), do: nil

  defp normalize_service_account_attrs(attrs) do
    attrs = Map.new(attrs || %{})

    %{
      gitlab_user_id: attrs[:gitlab_user_id] || attrs["gitlab_user_id"],
      username: attrs[:username] || attrs["username"],
      name: attrs[:name] || attrs["name"],
      web_url: attrs[:web_url] || attrs["web_url"],
      scopes: normalize_scopes(attrs[:scopes] || attrs["scopes"])
    }
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
    |> Map.update(:gitlab_user_id, nil, &to_string/1)
  end

  defp normalize_scopes(scopes) when is_binary(scopes), do: String.split(scopes, ~r/[\s,]+/, trim: true)
  defp normalize_scopes(scopes) when is_list(scopes), do: Enum.map(scopes, &to_string/1)
  defp normalize_scopes(_scopes), do: []

  defp oauth_scopes(attrs) do
    scope = attrs["scope"] || attrs[:scope] || attrs["scopes"] || attrs[:scopes] || []

    cond do
      is_binary(scope) -> String.split(scope, ~r/[\s,]+/, trim: true)
      is_list(scope) -> Enum.map(scope, &to_string/1)
      true -> []
    end
  end

  defp oauth_expires_at(attrs, now) do
    expires_in = attrs["expires_in"] || attrs[:expires_in]

    case expires_in do
      seconds when is_integer(seconds) and seconds > 0 ->
        DateTime.add(now, seconds, :second)

      seconds when is_binary(seconds) ->
        case Integer.parse(seconds) do
          {int, ""} when int > 0 -> DateTime.add(now, int, :second)
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp normalize_identity(attrs, now) do
    attrs = Map.new(attrs)
    issuer = attrs[:issuer] || attrs["issuer"]
    gitlab_user_id = attrs[:gitlab_user_id] || attrs["gitlab_user_id"] || attrs[:sub] || attrs["sub"]
    sub = attrs[:sub] || attrs["sub"] || gitlab_user_id

    %{
      id: attrs[:id] || attrs["id"] || Ecto.UUID.generate(),
      issuer: issuer,
      gitlab_user_id: to_string(gitlab_user_id),
      sub: to_string(sub),
      username: attrs[:username] || attrs["username"],
      name: attrs[:name] || attrs["name"],
      email: attrs[:email] || attrs["email"],
      avatar_url: attrs[:avatar_url] || attrs["avatar_url"],
      profile_url: attrs[:profile_url] || attrs["profile_url"],
      raw_claims: attrs[:raw_claims] || attrs["raw_claims"] || %{},
      last_login_at: now,
      inserted_at: attrs[:inserted_at] || attrs["inserted_at"] || now,
      updated_at: now
    }
  end

  defp normalize_project_membership(identity_id, project_setting_id, attrs, now) do
    attrs = Map.new(attrs)
    access_level = attrs[:access_level] || attrs["access_level"] || 0

    %{
      id: attrs[:id] || attrs["id"] || Ecto.UUID.generate(),
      identity_id: identity_id,
      gitlab_project_setting_id: project_setting_id,
      gitlab_user_id: to_string(attrs[:gitlab_user_id] || attrs["gitlab_user_id"]),
      username: attrs[:username] || attrs["username"],
      name: attrs[:name] || attrs["name"],
      access_level: access_level,
      expires_at: attrs[:expires_at] || attrs["expires_at"],
      state: attrs[:state] || attrs["state"],
      last_checked_at: now,
      raw_gitlab: attrs[:raw_gitlab] || attrs["raw_gitlab"] || %{},
      inserted_at: attrs[:inserted_at] || attrs["inserted_at"] || now,
      updated_at: now
    }
  end

  defp identity_key(%{issuer: issuer, gitlab_user_id: gitlab_user_id}), do: "#{issuer}:#{gitlab_user_id}"
  defp membership_key(identity_id, project_setting_id), do: "#{identity_id}:#{project_setting_id}"

  defp backfill_issue_project_setting(state, project) when is_map(project) do
    project = Map.new(project)
    project_setting_id = project[:id] || project["id"]
    gitlab_project_id = project[:project_id] || project["project_id"]

    cond do
      is_nil(project_setting_id) or is_nil(gitlab_project_id) ->
        {state, 0}

      true ->
        now = now()

        {issues, count} =
          Enum.reduce(state.issues, {%{}, 0}, fn {issue_id, issue}, {issues, count} ->
            if missing_project_setting_id?(issue) and same_gitlab_project?(issue, gitlab_project_id) do
              issue =
                issue
                |> Map.put(:gitlab_project_setting_id, project_setting_id)
                |> Map.put(:updated_at, now)

              {Map.put(issues, issue_id, issue), count + 1}
            else
              {Map.put(issues, issue_id, issue), count}
            end
          end)

        {%{state | issues: issues}, count}
    end
  end

  defp backfill_issue_project_setting(state, _project), do: {state, 0}

  defp missing_project_setting_id?(issue) do
    is_nil(issue[:gitlab_project_setting_id] || issue["gitlab_project_setting_id"])
  end

  defp same_gitlab_project?(issue, project_id) do
    issue_project_id = issue[:gitlab_project_id] || issue["gitlab_project_id"] || issue[:project_id] || issue["project_id"]
    not is_nil(issue_project_id) and to_string(issue_project_id) == to_string(project_id)
  end

  defp project_for_issue_attrs(state, attrs) do
    attrs = Map.new(attrs)
    gitlab_project_id = attrs[:gitlab_project_id] || attrs["gitlab_project_id"] || attrs[:project_id] || attrs["project_id"]

    case find_project(state.projects, %{project_id: gitlab_project_id, api_root: state.project && state.project[:api_root]}) do
      %{project_id: _} = project ->
        project

      _ ->
        fallback_project_for_issue_attrs(state.project, gitlab_project_id)
    end
  end

  defp fallback_project_for_issue_attrs(project, _gitlab_project_id), do: project

  defp issue_local_id(attrs) do
    project_id = attrs[:gitlab_project_id] || attrs["gitlab_project_id"] || attrs[:project_id] || attrs["project_id"]
    iid = attrs[:iid] || attrs["iid"]
    "gitlab-#{project_id}-#{iid}"
  end

  defp normalize_issue(attrs, existing, now, project) do
    attrs = Map.new(attrs)
    local_id = issue_local_id(attrs)

    existing
    |> Map.merge(attrs)
    |> maybe_put_project_setting_id(project)
    |> Map.put(:id, local_id)
    |> Map.put_new(:inserted_at, now)
    |> Map.put(:updated_at, now)
    |> Map.update(:labels, [], &(&1 || []))
    |> Map.update(:assignees, [], &(&1 || []))
  end

  defp maybe_put_project_setting_id(issue, %{id: id}), do: Map.put(issue, :gitlab_project_setting_id, id)
  defp maybe_put_project_setting_id(issue, _project), do: issue

  defp default_workflow_state(issue_id, now) do
    %{
      id: Ecto.UUID.generate(),
      gitlab_issue_id: issue_id,
      status: "backlog",
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

  defp hydrate_workflow_state(workflow) do
    workflow
    |> hydrate_datetime_fields([:claimed_at, :last_transition_at, :inserted_at, :updated_at])
    |> Map.update(:status, "backlog", &normalize_persisted_workflow_status/1)
  end

  defp normalize_persisted_workflow_status(status) do
    status = normalize_status(status)

    cond do
      status == "blocked" -> "todo"
      status in @workflow_statuses -> status
      true -> "backlog"
    end
  end

  defp normalize_note(issue_id, attrs, now) do
    attrs = Map.new(attrs)

    attrs
    |> Map.put(:id, "note-#{issue_id}-#{attrs[:note_id] || attrs["note_id"]}")
    |> Map.put(:gitlab_issue_id, issue_id)
    |> Map.put_new(:discussion_reply, false)
    |> Map.put_new(:discussion_individual_note, false)
    |> Map.put_new(:inserted_at, now)
    |> Map.put(:updated_at, now)
  end

  defp normalize_merge_request(project_setting_id, entry, now) do
    entry = Map.new(entry)
    issue_id = entry[:issue_id] || entry["issue_id"]
    attrs = entry[:attrs] || entry["attrs"] || %{}
    attrs = Map.new(attrs)

    if is_binary(issue_id) do
      attrs
      |> Map.put(:id, "merge-request-#{issue_id}-#{attrs[:merge_request_id] || attrs["merge_request_id"]}")
      |> Map.put(:gitlab_project_setting_id, project_setting_id)
      |> Map.put(:gitlab_issue_id, issue_id)
      |> Map.update(:labels, [], &(&1 || []))
      |> Map.update(:assignees, [], &(&1 || []))
      |> Map.update(:reviewers, [], &(&1 || []))
      |> Map.put_new(:draft, false)
      |> Map.put_new(:work_in_progress, false)
      |> Map.put_new(:inserted_at, now)
      |> Map.put(:updated_at, now)
    end
  end

  defp sort_merge_requests(merge_requests) do
    Enum.sort_by(merge_requests, fn merge_request ->
      {merge_request[:gitlab_updated_at] || merge_request["gitlab_updated_at"] || merge_request[:updated_at] || merge_request["updated_at"], merge_request[:iid] || merge_request["iid"] || 0}
    end)
    |> Enum.reverse()
  end

  defp normalize_registered_agent(attrs, now) do
    attrs = Map.new(attrs)
    provider = attrs[:provider] || attrs["provider"]
    auth_mode = attrs[:auth_mode] || attrs["auth_mode"]
    codex_home = attrs[:codex_home] || attrs["codex_home"]

    cond do
      provider not in @registered_agent_providers ->
        {:error, :invalid_provider}

      auth_mode not in @registered_agent_auth_modes ->
        {:error, :invalid_auth_mode}

      not is_binary(codex_home) or String.trim(codex_home) == "" ->
        {:error, :codex_home_required}

      (attrs[:usage_status] || attrs["usage_status"] || "unknown") not in @registered_agent_usage_statuses ->
        {:error, :invalid_usage_status}

      (attrs[:mcp_install_status] || attrs["mcp_install_status"] || "pending") not in @registered_agent_mcp_install_statuses ->
        {:error, :invalid_mcp_install_status}

      not valid_string_list?(attrs[:mcp_server_names] || attrs["mcp_server_names"] || []) ->
        {:error, :invalid_mcp_server_names}

      true ->
        {:ok,
         %{
           id: attrs[:id] || attrs["id"] || Ecto.UUID.generate(),
           provider: provider,
           name: attrs[:name] || attrs["name"] || "Codex",
           auth_mode: auth_mode,
           codex_home: codex_home,
           credential_status: attrs[:credential_status] || attrs["credential_status"] || "pending",
           login_started_at: attrs[:login_started_at] || attrs["login_started_at"],
           last_login_exit_status: attrs[:last_login_exit_status] || attrs["last_login_exit_status"],
           last_login_message: attrs[:last_login_message] || attrs["last_login_message"],
           mcp_install_status: attrs[:mcp_install_status] || attrs["mcp_install_status"] || "pending",
           mcp_install_started_at: attrs[:mcp_install_started_at] || attrs["mcp_install_started_at"],
           mcp_install_finished_at: attrs[:mcp_install_finished_at] || attrs["mcp_install_finished_at"],
           mcp_install_exit_status: attrs[:mcp_install_exit_status] || attrs["mcp_install_exit_status"],
           mcp_install_message: attrs[:mcp_install_message] || attrs["mcp_install_message"],
           mcp_server_names: attrs[:mcp_server_names] || attrs["mcp_server_names"] || [],
           usage_status: attrs[:usage_status] || attrs["usage_status"] || "unknown",
           usage_snapshot: attrs[:usage_snapshot] || attrs["usage_snapshot"],
           usage_checked_at: attrs[:usage_checked_at] || attrs["usage_checked_at"],
           usage_error: attrs[:usage_error] || attrs["usage_error"],
           inserted_at: now,
           updated_at: now
         }}
    end
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
    unresolved_blocker_count = unresolved_blocker_count(state, issue.id)
    open_runtime_block_count = open_runtime_block_count(state, issue.id)

    issue
    |> Map.put(:identifier, issue_identifier(state, issue))
    |> Map.put(:workflow_state, workflow)
    |> Map.put(:workflow_status, workflow.status)
    |> Map.put(:priority, workflow.priority)
    |> Map.put(:blockers, blocker_dtos(state, issue.id))
    |> Map.put(:relations, relation_dtos(state, issue.id))
    |> Map.put(:is_blocked, unresolved_blocker_count > 0 or open_runtime_block_count > 0 or blocked_run?(state, issue.id))
    |> Map.put(:unresolved_blocker_count, unresolved_blocker_count)
    |> Map.put(:open_runtime_block_count, open_runtime_block_count)
    |> Map.put(:blocked_by_count, blocked_by_count(state, issue.id))
    |> Map.put(:active_run_id, active_run_id(state, issue.id))
    |> Map.put(:last_run_status, last_run_status(state, issue.id))
  end

  defp undecorate(issue),
    do:
      Map.drop(issue, [
        :workflow_state,
        :workflow_status,
        :priority,
        :blockers,
        :relations,
        :is_blocked,
        :unresolved_blocker_count,
        :open_runtime_block_count,
        :blocked_by_count,
        :active_run_id,
        :last_run_status
      ])

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
      is_blocked: decorated.is_blocked || false,
      unresolved_blocker_count: decorated.unresolved_blocker_count || 0,
      open_runtime_block_count: decorated.open_runtime_block_count || 0,
      blockers: decorated.blockers || [],
      blocked_by: blocker_refs(state, issue.id),
      notes_summary: notes_summary(state, issue.id),
      created_at: Map.get(decorated, :gitlab_created_at),
      updated_at: Map.get(decorated, :gitlab_updated_at)
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

        if Transitions.allowed?(previous_status, next_status, opts) do
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
            |> append_event("workflow_transitioned", Keyword.get(opts, :source, "user_ui"), %{from: previous_status, to: next_status, reason: Keyword.get(opts, :reason)},
              issue_id: issue_id,
              actor: Keyword.get(opts, :actor, "system")
            )

          {:ok, workflow, state}
        else
          {:error, :invalid_transition}
        end
    end
  end

  defp blocker_dtos(state, issue_id) do
    state.dependencies
    |> Map.values()
    |> Enum.filter(&(&1.blocked_issue_id == issue_id))
    |> Enum.map(fn edge ->
      issue_ref(state, edge.blocking_issue_id, reason: edge.reason)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp relation_dtos(state, issue_id) do
    %{
      related: related_issue_dtos(state, issue_id),
      blocks: blocked_issue_dtos(state, issue_id),
      blocked_by: blocker_dtos(state, issue_id)
    }
  end

  defp related_issue_dtos(state, issue_id) do
    state.relations
    |> Map.values()
    |> Enum.filter(&(&1.relation_type == "relates_to" and (&1.source_issue_id == issue_id or &1.target_issue_id == issue_id)))
    |> Enum.sort_by(& &1.inserted_at, DateTime)
    |> Enum.map(fn relation ->
      related_issue_id =
        if relation.source_issue_id == issue_id do
          relation.target_issue_id
        else
          relation.source_issue_id
        end

      issue_ref(state, related_issue_id,
        reason: relation.reason,
        relation_type: relation.relation_type,
        direction: if(relation.source_issue_id == issue_id, do: "outgoing", else: "incoming")
      )
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp blocked_issue_dtos(state, issue_id) do
    state.dependencies
    |> Map.values()
    |> Enum.filter(&(&1.blocking_issue_id == issue_id))
    |> Enum.map(fn edge ->
      issue_ref(state, edge.blocked_issue_id, reason: edge.reason)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp issue_ref(state, issue_id, extra) do
    with %{} = issue <- Map.get(state.issues, issue_id),
         %{} = workflow <- Map.get(state.workflow_states, issue_id) do
      %{
        issue_id: issue.id,
        iid: issue.iid,
        identifier: issue_identifier(state, issue),
        title: issue.title,
        status: workflow.status
      }
      |> Map.merge(Map.new(extra))
    else
      _ -> nil
    end
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

  defp unresolved_blocker_count(state, issue_id) do
    blocker_dtos(state, issue_id)
    |> Enum.count(&(&1.status != "done"))
  end

  defp open_runtime_block_count(state, issue_id) do
    state.runtime_blocks
    |> Map.values()
    |> Enum.count(&(&1.gitlab_issue_id == issue_id and is_nil(&1.resolved_at)))
  end

  defp blocked_run?(state, issue_id) do
    state.runs
    |> Map.values()
    |> Enum.any?(&(&1.gitlab_issue_id == issue_id and &1.status == "blocked"))
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
    unresolved_blocker_count(state, issue_id) > 0
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
  defp relation_key(source_issue_id, target_issue_id, relation_type), do: "#{source_issue_id}:#{target_issue_id}:#{relation_type}"

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
      project: state.project && public_project(state.project, state),
      registered_agents: Enum.map(state.registered_agent_order, &Map.get(state.registered_agents, &1)) |> Enum.reject(&is_nil/1),
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
        {:status, "blocked"} -> issue.is_blocked == true
        {:status, status} -> issue.workflow_status == status
        {:gitlab_state, state} -> issue.gitlab_state == state
        {:project_setting_id, project_setting_id} -> Map.get(issue, :gitlab_project_setting_id) == project_setting_id
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
        {:project_setting_id, project_setting_id} -> get_in(run, [:issue, :gitlab_project_setting_id]) == project_setting_id
        _ -> true
      end)
    end)
  end

  defp map_value(map, key, default) when is_map(map) and is_atom(key) do
    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, Atom.to_string(key)) -> Map.get(map, Atom.to_string(key))
      true -> default
    end
  end

  defp sort_notes(notes) do
    Enum.sort_by(notes, fn note ->
      {note_sort_time(Map.get(note, :gitlab_created_at) || Map.get(note, :inserted_at)), Map.get(note, :discussion_position) || 0, Map.get(note, :note_id) || 0}
    end)
  end

  defp note_sort_time(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :microsecond)
  defp note_sort_time(_datetime), do: 0

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

  defp normalize_relation_type(type) when is_binary(type), do: type |> String.trim() |> String.downcase()
  defp normalize_relation_type(type), do: to_string(type) |> normalize_relation_type()

  defp normalize_priority(priority) when is_binary(priority), do: priority |> String.trim() |> String.downcase()
  defp normalize_priority(priority), do: to_string(priority)

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp valid_string_list?(values), do: is_list(values) and Enum.all?(values, &is_binary/1)

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
