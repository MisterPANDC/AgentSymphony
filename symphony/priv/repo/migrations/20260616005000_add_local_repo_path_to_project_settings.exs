defmodule SymphonyElixir.Repo.Migrations.AddLocalRepoPathToProjectSettings do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE gitlab_project_settings ADD COLUMN IF NOT EXISTS local_repo_path text")
  end

  def down do
    execute("ALTER TABLE gitlab_project_settings DROP COLUMN IF EXISTS local_repo_path")
  end
end
