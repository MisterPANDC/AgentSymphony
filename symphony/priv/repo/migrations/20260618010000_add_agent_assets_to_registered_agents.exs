defmodule SymphonyElixir.Repo.Migrations.AddAgentAssetsToRegisteredAgents do
  use Ecto.Migration

  def change do
    alter table(:registered_agents) do
      add(:asset_install_status, :text, null: false, default: "pending")
      add(:asset_install_started_at, :utc_datetime_usec)
      add(:asset_install_finished_at, :utc_datetime_usec)
      add(:asset_install_exit_status, :integer)
      add(:asset_install_message, :text)
      add(:skill_names, {:array, :text}, null: false, default: [])
      add(:plugin_names, {:array, :text}, null: false, default: [])
    end

    create_check_constraint(
      :registered_agents,
      :registered_agents_asset_install_status_check,
      "asset_install_status in ('pending', 'installing', 'configured', 'failed')"
    )
  end

  defp create_check_constraint(table, name, check) do
    execute(
      """
      DO $$
      BEGIN
        ALTER TABLE #{table} ADD CONSTRAINT #{name} CHECK (#{check});
      EXCEPTION
        WHEN duplicate_object THEN NULL;
      END
      $$;
      """,
      "ALTER TABLE #{table} DROP CONSTRAINT IF EXISTS #{name};"
    )
  end
end
