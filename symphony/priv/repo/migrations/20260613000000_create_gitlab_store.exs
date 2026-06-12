defmodule SymphonyElixir.Repo.Migrations.CreateGitlabStore do
  use Ecto.Migration

  def change do
    create table(:gitlab_project_settings, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :api_root, :text, null: false
      add :project_ref, :text, null: false
      add :project_id, :bigint
      add :path_with_namespace, :text
      add :name, :text
      add :web_url, :text
      add :visibility, :text
      add :last_validated_at, :utc_datetime_usec
      add :last_validation_error, :text
      add :read_only, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create table(:gitlab_issues, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :gitlab_project_setting_id, references(:gitlab_project_settings, type: :uuid, on_delete: :delete_all), null: false
      add :gitlab_issue_id, :bigint, null: false
      add :gitlab_project_id, :bigint, null: false
      add :iid, :integer, null: false
      add :web_url, :text, null: false
      add :title, :text, null: false
      add :description, :text
      add :description_preview, :text
      add :gitlab_state, :text, null: false
      add :labels, :map, null: false, default: fragment("'[]'::jsonb")
      add :assignees, :map, null: false, default: fragment("'[]'::jsonb")
      add :author, :map
      add :milestone, :map
      add :due_date, :date
      add :confidential, :boolean, null: false, default: false
      add :gitlab_created_at, :utc_datetime_usec
      add :gitlab_updated_at, :utc_datetime_usec
      add :closed_at, :utc_datetime_usec
      add :last_synced_at, :utc_datetime_usec
      add :raw_gitlab, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:gitlab_issues, [:gitlab_project_setting_id, :iid])
    create unique_index(:gitlab_issues, [:gitlab_project_setting_id, :gitlab_issue_id])
    create index(:gitlab_issues, [:gitlab_state])
    create index(:gitlab_issues, [:gitlab_updated_at])

    create table(:gitlab_issue_notes, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :gitlab_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :delete_all), null: false
      add :note_id, :bigint, null: false
      add :body, :text, null: false
      add :author, :map
      add :system, :boolean, null: false, default: false
      add :internal, :boolean, null: false, default: false
      add :resolvable, :boolean, null: false, default: false
      add :gitlab_created_at, :utc_datetime_usec
      add :gitlab_updated_at, :utc_datetime_usec
      add :raw_gitlab, :map

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:gitlab_issue_notes, [:gitlab_issue_id, :note_id])

    create table(:issue_workflow_states, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :gitlab_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :delete_all), null: false
      add :status, :text, null: false
      add :priority, :text, null: false, default: "none"
      add :rank, :numeric
      add :claimed_by, :text
      add :claimed_at, :utc_datetime_usec
      add :last_transition_at, :utc_datetime_usec
      add :last_transition_reason, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:issue_workflow_states, [:gitlab_issue_id])
    create index(:issue_workflow_states, [:status])

    create constraint(:issue_workflow_states, :issue_workflow_states_status_check,
             check: "status in ('triage', 'todo', 'in_progress', 'blocked', 'review', 'done', 'canceled')"
           )

    create constraint(:issue_workflow_states, :issue_workflow_states_priority_check,
             check: "priority in ('none', 'low', 'medium', 'high', 'urgent')"
           )

    create table(:issue_dependencies, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :blocked_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :delete_all), null: false
      add :blocking_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :delete_all), null: false
      add :created_by, :text, null: false, default: "local_operator"
      add :reason, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:issue_dependencies, [:blocked_issue_id, :blocking_issue_id])
    create constraint(:issue_dependencies, :issue_dependencies_not_self_check, check: "blocked_issue_id != blocking_issue_id")

    create table(:issue_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :gitlab_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :nilify_all)
      add :event_type, :text, null: false
      add :source, :text, null: false
      add :actor, :text
      add :payload, :map, null: false, default: %{}
      add :run_id, :uuid

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:issue_events, [:gitlab_issue_id])
    create index(:issue_events, [:event_type])
    create constraint(:issue_events, :issue_events_source_check, check: "source in ('gitlab_sync', 'local_ui', 'agent', 'system')")

    create table(:sync_cursors, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :source, :text, null: false
      add :cursor_name, :text, null: false
      add :cursor_value, :text
      add :last_success_at, :utc_datetime_usec
      add :last_attempt_at, :utc_datetime_usec
      add :last_error, :text
      add :last_error_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:sync_cursors, [:source, :cursor_name])

    create table(:agent_runs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :gitlab_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :delete_all), null: false
      add :run_number, :integer, null: false
      add :status, :text, null: false
      add :mode, :text, null: false, default: "workflow"
      add :workspace_path, :text
      add :codex_thread_id, :text
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :last_heartbeat_at, :utc_datetime_usec
      add :exit_reason, :text
      add :error_message, :text
      add :blocked_reason, :text
      add :needs_operator_input, :boolean, null: false, default: false
      add :summary, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_runs, [:gitlab_issue_id, :run_number])
    create index(:agent_runs, [:status])
    create constraint(:agent_runs, :agent_runs_status_check,
             check: "status in ('queued', 'starting', 'running', 'blocked', 'succeeded', 'failed', 'canceled', 'stale')"
           )

    create table(:agent_run_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :agent_run_id, references(:agent_runs, type: :uuid, on_delete: :delete_all), null: false
      add :event_type, :text, null: false
      add :message, :text
      add :payload, :map, null: false, default: %{}

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:agent_run_events, [:agent_run_id])
    create constraint(:agent_run_events, :agent_run_events_type_check,
             check:
               "event_type in ('queued', 'workspace_created', 'codex_started', 'turn_started', 'turn_finished', 'comment_posted', 'status_changed', 'blocked', 'operator_input_required', 'succeeded', 'failed', 'canceled', 'heartbeat')"
           )

    create table(:runtime_blocks, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :gitlab_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :delete_all), null: false
      add :agent_run_id, references(:agent_runs, type: :uuid, on_delete: :nilify_all)
      add :block_type, :text, null: false
      add :message, :text
      add :payload, :map, null: false, default: %{}
      add :resolved_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create index(:runtime_blocks, [:gitlab_issue_id])
    create index(:runtime_blocks, [:resolved_at])
    create constraint(:runtime_blocks, :runtime_blocks_type_check,
             check:
               "block_type in ('operator_input', 'approval_required', 'mcp_elicitation', 'sandbox_rejection', 'external_failure', 'blocked_by_dependency')"
           )
  end
end
