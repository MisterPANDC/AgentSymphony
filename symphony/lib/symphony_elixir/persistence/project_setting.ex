defmodule SymphonyElixir.Persistence.ProjectSetting do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gitlab_project_settings" do
    field(:api_root, :string)
    field(:project_ref, :string)
    field(:project_id, :integer)
    field(:path_with_namespace, :string)
    field(:name, :string)
    field(:web_url, :string)
    field(:visibility, :string)
    field(:last_validated_at, :utc_datetime_usec)
    field(:last_validation_error, :string)
    field(:read_only, :boolean, default: false)
    field(:automation_credential_mode, :string, default: "project_access_token")
    field(:local_repo_path, :string)
    field(:encrypted_project_access_token, :string)
    field(:project_access_token_set_by_identity_id, :binary_id)
    field(:project_access_token_set_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(api_root project_ref project_id path_with_namespace name web_url visibility last_validated_at last_validation_error read_only automation_credential_mode local_repo_path encrypted_project_access_token project_access_token_set_by_identity_id project_access_token_set_at)a
  @required ~w(api_root project_ref read_only automation_credential_mode)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:automation_credential_mode, ["project_access_token", "service_account"])
  end
end
