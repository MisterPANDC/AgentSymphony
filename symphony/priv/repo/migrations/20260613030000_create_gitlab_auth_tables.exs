defmodule SymphonyElixir.Repo.Migrations.CreateGitlabAuthTables do
  use Ecto.Migration

  def change do
    create table(:gitlab_identities, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :issuer, :text, null: false
      add :gitlab_user_id, :text, null: false
      add :sub, :text, null: false
      add :username, :text, null: false
      add :name, :text
      add :email, :text
      add :avatar_url, :text
      add :profile_url, :text
      add :raw_claims, :map, null: false, default: %{}
      add :last_login_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:gitlab_identities, [:issuer, :gitlab_user_id])
    create unique_index(:gitlab_identities, [:issuer, :sub])
    create index(:gitlab_identities, [:username])

    create table(:gitlab_project_memberships, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :identity_id, references(:gitlab_identities, type: :uuid, on_delete: :delete_all), null: false

      add :gitlab_project_setting_id,
          references(:gitlab_project_settings, type: :uuid, on_delete: :delete_all),
          null: false

      add :gitlab_user_id, :text, null: false
      add :username, :text, null: false
      add :name, :text
      add :access_level, :integer, null: false
      add :role, :text, null: false
      add :expires_at, :date
      add :state, :text
      add :last_checked_at, :utc_datetime_usec, null: false
      add :raw_gitlab, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:gitlab_project_memberships, [:identity_id, :gitlab_project_setting_id])
    create index(:gitlab_project_memberships, [:gitlab_project_setting_id, :access_level])
  end
end
