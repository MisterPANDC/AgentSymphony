defmodule SymphonyElixir.Repo.Migrations.CreateIssueRelations do
  use Ecto.Migration

  def change do
    create table(:issue_relations, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :source_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :delete_all), null: false
      add :target_issue_id, references(:gitlab_issues, type: :uuid, on_delete: :delete_all), null: false
      add :relation_type, :text, null: false
      add :created_by, :text, null: false, default: "local_operator"
      add :reason, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:issue_relations, [:source_issue_id, :target_issue_id, :relation_type])
    create index(:issue_relations, [:target_issue_id])
    create constraint(:issue_relations, :issue_relations_not_self_check, check: "source_issue_id != target_issue_id")
    create constraint(:issue_relations, :issue_relations_type_check, check: "relation_type in ('relates_to')")
  end
end
