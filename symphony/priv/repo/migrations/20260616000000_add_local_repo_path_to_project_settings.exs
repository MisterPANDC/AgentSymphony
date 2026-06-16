defmodule SymphonyElixir.Repo.Migrations.AddLocalRepoPathToProjectSettings do
  use Ecto.Migration

  def change do
    alter table(:gitlab_project_settings) do
      add(:local_repo_path, :text)
    end
  end
end
