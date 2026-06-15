defmodule SymphonyElixir.Persistence.MergeRequest do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Persistence.{Issue, ProjectSetting}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gitlab_merge_requests" do
    belongs_to(:project_setting, ProjectSetting, foreign_key: :gitlab_project_setting_id)
    belongs_to(:issue, Issue, foreign_key: :gitlab_issue_id)

    field(:merge_request_id, :integer)
    field(:iid, :integer)
    field(:title, :string)
    field(:description, :string)
    field(:state, :string)
    field(:draft, :boolean, default: false)
    field(:work_in_progress, :boolean, default: false)
    field(:web_url, :string)
    field(:source_branch, :string)
    field(:target_branch, :string)
    field(:merge_status, :string)
    field(:detailed_merge_status, :string)
    field(:labels, SymphonyElixir.Persistence.JsonList, default: [])
    field(:author, :map)
    field(:assignees, SymphonyElixir.Persistence.JsonList, default: [])
    field(:reviewers, SymphonyElixir.Persistence.JsonList, default: [])
    field(:milestone, :map)
    field(:user_notes_count, :integer)
    field(:upvotes, :integer)
    field(:downvotes, :integer)
    field(:changes_count, :string)
    field(:references, :map)
    field(:head_pipeline, :map)
    field(:gitlab_created_at, :utc_datetime_usec)
    field(:gitlab_updated_at, :utc_datetime_usec)
    field(:merged_at, :utc_datetime_usec)
    field(:closed_at, :utc_datetime_usec)
    field(:last_synced_at, :utc_datetime_usec)
    field(:raw_gitlab, :map)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(gitlab_project_setting_id gitlab_issue_id merge_request_id iid title description state draft work_in_progress web_url source_branch target_branch merge_status detailed_merge_status labels author assignees reviewers milestone user_notes_count upvotes downvotes changes_count references head_pipeline gitlab_created_at gitlab_updated_at merged_at closed_at last_synced_at raw_gitlab)a
  @required ~w(gitlab_project_setting_id gitlab_issue_id merge_request_id iid title state draft work_in_progress web_url labels assignees reviewers)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(merge_request, attrs) do
    merge_request
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
