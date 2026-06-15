defmodule SymphonyElixir.Repo.Migrations.RemoveBlockedWorkflowStatus do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE issue_workflow_states DROP CONSTRAINT IF EXISTS issue_workflow_states_status_check")
    execute("UPDATE issue_workflow_states SET status = 'todo' WHERE status = 'blocked'")
    execute("UPDATE issue_workflow_states SET status = 'backlog' WHERE status NOT IN ('backlog', 'todo', 'in_progress', 'review', 'merging', 'rework', 'done', 'canceled')")

    create constraint(:issue_workflow_states, :issue_workflow_states_status_check,
             check: "status in ('backlog', 'todo', 'in_progress', 'review', 'merging', 'rework', 'done', 'canceled')"
           )
  end

  def down do
    execute("ALTER TABLE issue_workflow_states DROP CONSTRAINT IF EXISTS issue_workflow_states_status_check")

    create constraint(:issue_workflow_states, :issue_workflow_states_status_check,
             check: "status in ('backlog', 'todo', 'in_progress', 'blocked', 'review', 'merging', 'rework', 'done', 'canceled')"
           )
  end
end
