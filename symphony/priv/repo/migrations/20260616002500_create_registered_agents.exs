defmodule SymphonyElixir.Repo.Migrations.CreateRegisteredAgents do
  use Ecto.Migration

  def up do
    create_if_not_exists table(:registered_agents, primary_key: false) do
      add(:id, :uuid, primary_key: true)
      add(:provider, :text, null: false)
      add(:name, :text, null: false)
      add(:auth_mode, :text, null: false)
      add(:codex_home, :text, null: false)
      add(:credential_status, :text, null: false, default: "pending")
      add(:login_started_at, :utc_datetime_usec)
      add(:last_login_exit_status, :integer)
      add(:last_login_message, :text)
      add(:mcp_install_status, :text, null: false, default: "pending")
      add(:mcp_install_started_at, :utc_datetime_usec)
      add(:mcp_install_finished_at, :utc_datetime_usec)
      add(:mcp_install_exit_status, :integer)
      add(:mcp_install_message, :text)
      add(:mcp_server_names, {:array, :text}, null: false, default: [])
      add(:usage_status, :text, null: false, default: "unknown")
      add(:usage_snapshot, :map)
      add(:usage_checked_at, :utc_datetime_usec)
      add(:usage_error, :text)

      timestamps(type: :utc_datetime_usec)
    end

    create_if_not_exists(unique_index(:registered_agents, [:codex_home]))
    create_if_not_exists(index(:registered_agents, [:provider]))

    create_check_constraint(
      :registered_agents,
      :registered_agents_provider_check,
      "provider in ('codex')"
    )

    create_check_constraint(
      :registered_agents,
      :registered_agents_auth_mode_check,
      "auth_mode in ('subscription', 'api', 'auth_json')"
    )

    create_check_constraint(
      :registered_agents,
      :registered_agents_credential_status_check,
      "credential_status in ('pending', 'login_started', 'configured', 'failed')"
    )

    create_check_constraint(
      :registered_agents,
      :registered_agents_mcp_install_status_check,
      "mcp_install_status in ('pending', 'installing', 'configured', 'failed')"
    )

    create_check_constraint(
      :registered_agents,
      :registered_agents_usage_status_check,
      "usage_status in ('unknown', 'available', 'unavailable', 'not_applicable')"
    )
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
