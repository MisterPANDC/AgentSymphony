defmodule SymphonyElixir.Repo.Migrations.AddGitlabOauthAndProjectTokens do
  use Ecto.Migration

  def change do
    alter table(:gitlab_project_settings) do
      add :encrypted_project_access_token, :text
      add :project_access_token_set_by_identity_id,
          references(:gitlab_identities, type: :uuid, on_delete: :nilify_all)
      add :project_access_token_set_at, :utc_datetime_usec
    end

    create unique_index(:gitlab_project_settings, [:api_root, :project_id], where: "project_id is not null")
    create unique_index(:gitlab_project_settings, [:api_root, :project_ref])

    create table(:gitlab_oauth_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :identity_id, references(:gitlab_identities, type: :uuid, on_delete: :delete_all), null: false
      add :encrypted_access_token, :text, null: false
      add :encrypted_refresh_token, :text
      add :scopes, {:array, :text}, null: false, default: []
      add :token_type, :text
      add :expires_at, :utc_datetime_usec
      add :last_refreshed_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:gitlab_oauth_tokens, [:identity_id])
  end
end
