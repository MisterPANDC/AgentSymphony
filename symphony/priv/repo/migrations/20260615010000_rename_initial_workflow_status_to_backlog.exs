defmodule SymphonyElixir.Repo.Migrations.RenameInitialWorkflowStatusToBacklog do
  use Ecto.Migration

  @valid_statuses "'backlog', 'todo', 'in_progress', 'review', 'merging', 'rework', 'done', 'canceled'"

  def up do
    execute("ALTER TABLE issue_workflow_states DROP CONSTRAINT IF EXISTS issue_workflow_states_status_check")
    execute("UPDATE issue_workflow_states SET status = 'backlog' WHERE status NOT IN (#{@valid_statuses})")

    create(constraint(:issue_workflow_states, :issue_workflow_states_status_check, check: "status in (#{@valid_statuses})"))
  end

  def down do
    execute("ALTER TABLE issue_workflow_states DROP CONSTRAINT IF EXISTS issue_workflow_states_status_check")

    create(constraint(:issue_workflow_states, :issue_workflow_states_status_check, check: "status in (#{@valid_statuses})"))
  end
end
