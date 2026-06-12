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

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(api_root project_ref project_id path_with_namespace name web_url visibility last_validated_at last_validation_error read_only)a
  @required ~w(api_root project_ref read_only)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(setting, attrs) do
    setting
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
