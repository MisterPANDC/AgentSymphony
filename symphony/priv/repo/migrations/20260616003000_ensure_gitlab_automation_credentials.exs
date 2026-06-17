defmodule SymphonyElixir.Repo.Migrations.EnsureGitlabAutomationCredentials do
  use Ecto.Migration

  def up do
    alter table(:gitlab_project_settings) do
      add_if_not_exists(:automation_credential_mode, :text,
        null: false,
        default: "project_access_token"
      )
    end

    create_check_constraint(
      :gitlab_project_settings,
      :automation_credential_mode_valid,
      "automation_credential_mode in ('project_access_token', 'service_account')"
    )

    create_if_not_exists table(:gitlab_service_account_credentials, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:api_root, :text, null: false)
      add(:encrypted_service_account_token, :text)

      add(
        :service_account_token_set_by_identity_id,
        references(:gitlab_identities, type: :uuid, on_delete: :nilify_all)
      )

      add(:service_account_token_set_at, :utc_datetime_usec)
      add(:last_validated_at, :utc_datetime_usec)
      add(:last_validation_error, :text)
      add(:gitlab_user_id, :text)
      add(:username, :text)
      add(:name, :text)
      add(:web_url, :text)
      add(:scopes, {:array, :text}, null: false, default: [])

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(unique_index(:gitlab_service_account_credentials, [:api_root]))
  end

  def down do
    :ok
  end

  defp create_check_constraint(table, name, check) do
    execute("""
    DO $$
    BEGIN
      ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{check});
    EXCEPTION
      WHEN duplicate_object THEN NULL;
    END
    $$;
    """)
  end
end
