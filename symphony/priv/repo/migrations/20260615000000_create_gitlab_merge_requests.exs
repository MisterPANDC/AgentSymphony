defmodule SymphonyElixir.Repo.Migrations.CreateGitlabMergeRequests do
  use Ecto.Migration

  def change do
    create table(:gitlab_merge_requests, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:gitlab_project_setting_id, references(:gitlab_project_settings, type: :uuid, on_delete: :delete_all), null: false)
      add(:gitlab_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :delete_all), null: false)
      add(:merge_request_id, :bigint, null: false)
      add(:iid, :integer, null: false)
      add(:title, :text, null: false)
      add(:description, :text)
      add(:state, :text, null: false)
      add(:draft, :boolean, null: false, default: false)
      add(:work_in_progress, :boolean, null: false, default: false)
      add(:web_url, :text, null: false)
      add(:source_branch, :text)
      add(:target_branch, :text)
      add(:merge_status, :text)
      add(:detailed_merge_status, :text)
      add(:labels, :map, null: false, default: fragment("'[]'::jsonb"))
      add(:author, :map)
      add(:assignees, :map, null: false, default: fragment("'[]'::jsonb"))
      add(:reviewers, :map, null: false, default: fragment("'[]'::jsonb"))
      add(:milestone, :map)
      add(:user_notes_count, :integer)
      add(:upvotes, :integer)
      add(:downvotes, :integer)
      add(:changes_count, :text)
      add(:references, :map)
      add(:head_pipeline, :map)
      add(:gitlab_created_at, :utc_datetime_usec)
      add(:gitlab_updated_at, :utc_datetime_usec)
      add(:merged_at, :utc_datetime_usec)
      add(:closed_at, :utc_datetime_usec)
      add(:last_synced_at, :utc_datetime_usec)
      add(:raw_gitlab, :map)

      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:gitlab_merge_requests, [:gitlab_issue_id, :merge_request_id]))
    create(index(:gitlab_merge_requests, [:gitlab_project_setting_id]))
    create(index(:gitlab_merge_requests, [:gitlab_issue_id]))
    create(index(:gitlab_merge_requests, [:state]))
    create(index(:gitlab_merge_requests, [:gitlab_updated_at]))
  end
end
