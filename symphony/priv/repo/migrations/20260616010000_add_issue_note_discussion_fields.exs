defmodule SymphonyElixir.Repo.Migrations.AddIssueNoteDiscussionFields do
  use Ecto.Migration

  def change do
    alter table(:gitlab_issue_notes) do
      add(:discussion_id, :text)
      add(:discussion_reply, :boolean, null: false, default: false)
      add(:discussion_individual_note, :boolean, null: false, default: false)
      add(:discussion_position, :integer)
    end

    create(index(:gitlab_issue_notes, [:gitlab_issue_id, :discussion_id]))
  end
end
