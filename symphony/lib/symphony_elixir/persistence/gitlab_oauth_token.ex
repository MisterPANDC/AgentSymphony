defmodule SymphonyElixir.Persistence.GitLabOAuthToken do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gitlab_oauth_tokens" do
    field(:encrypted_access_token, :string)
    field(:encrypted_refresh_token, :string)
    field(:scopes, {:array, :string}, default: [])
    field(:token_type, :string)
    field(:expires_at, :utc_datetime_usec)
    field(:last_refreshed_at, :utc_datetime_usec)

    belongs_to(:identity, SymphonyElixir.Persistence.GitLabIdentity)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(identity_id encrypted_access_token encrypted_refresh_token scopes token_type expires_at last_refreshed_at)a
  @required ~w(identity_id encrypted_access_token)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(token, attrs) do
    token
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
