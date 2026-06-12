defmodule SymphonyElixir.Persistence.Issue do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Persistence.ProjectSetting

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gitlab_issues" do
    belongs_to(:project_setting, ProjectSetting, foreign_key: :gitlab_project_setting_id)

    field(:gitlab_issue_id, :integer)
    field(:gitlab_project_id, :integer)
    field(:iid, :integer)
    field(:web_url, :string)
    field(:title, :string)
    field(:description, :string)
    field(:description_preview, :string)
    field(:gitlab_state, :string)
    field(:labels, SymphonyElixir.Persistence.JsonList, default: [])
    field(:assignees, SymphonyElixir.Persistence.JsonList, default: [])
    field(:author, :map)
    field(:milestone, :map)
    field(:due_date, :date)
    field(:confidential, :boolean, default: false)
    field(:gitlab_created_at, :utc_datetime_usec)
    field(:gitlab_updated_at, :utc_datetime_usec)
    field(:closed_at, :utc_datetime_usec)
    field(:last_synced_at, :utc_datetime_usec)
    field(:raw_gitlab, :map)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(gitlab_project_setting_id gitlab_issue_id gitlab_project_id iid web_url title description description_preview gitlab_state labels assignees author milestone due_date confidential gitlab_created_at gitlab_updated_at closed_at last_synced_at raw_gitlab)a
  @required ~w(gitlab_project_setting_id gitlab_issue_id gitlab_project_id iid web_url title gitlab_state labels assignees confidential)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(issue, attrs) do
    issue
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
