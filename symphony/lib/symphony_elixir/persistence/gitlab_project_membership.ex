defmodule SymphonyElixir.Persistence.GitLabProjectMembership do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gitlab_project_memberships" do
    field(:gitlab_user_id, :string)
    field(:username, :string)
    field(:name, :string)
    field(:access_level, :integer)
    field(:role, :string)
    field(:expires_at, :date)
    field(:state, :string)
    field(:last_checked_at, :utc_datetime_usec)
    field(:raw_gitlab, :map, default: %{})

    belongs_to(:identity, SymphonyElixir.Persistence.GitLabIdentity)
    belongs_to(:project_setting, SymphonyElixir.Persistence.ProjectSetting, foreign_key: :gitlab_project_setting_id)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(identity_id gitlab_project_setting_id gitlab_user_id username name access_level role expires_at state last_checked_at raw_gitlab)a
  @required ~w(identity_id gitlab_project_setting_id gitlab_user_id username access_level role last_checked_at)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(membership, attrs) do
    membership
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
