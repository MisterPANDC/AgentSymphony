defmodule SymphonyElixir.Persistence.GitLabIdentity do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gitlab_identities" do
    field(:issuer, :string)
    field(:gitlab_user_id, :string)
    field(:sub, :string)
    field(:username, :string)
    field(:name, :string)
    field(:email, :string)
    field(:avatar_url, :string)
    field(:profile_url, :string)
    field(:raw_claims, :map, default: %{})
    field(:last_login_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(issuer gitlab_user_id sub username name email avatar_url profile_url raw_claims last_login_at)a
  @required ~w(issuer gitlab_user_id sub username last_login_at)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(identity, attrs) do
    identity
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
