defmodule SymphonyElixir.Repo.Migrations.RemoveGitlabProjectMembershipRole do
  use Ecto.Migration

  def change do
    alter table(:gitlab_project_memberships) do
      remove :role, :text
    end
  end
end
