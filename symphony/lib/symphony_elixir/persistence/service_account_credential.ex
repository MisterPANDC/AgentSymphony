defmodule SymphonyElixir.Persistence.ServiceAccountCredential do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gitlab_service_account_credentials" do
    field(:api_root, :string)
    field(:encrypted_service_account_token, :string)
    field(:service_account_token_set_by_identity_id, :binary_id)
    field(:service_account_token_set_at, :utc_datetime_usec)
    field(:last_validated_at, :utc_datetime_usec)
    field(:last_validation_error, :string)
    field(:gitlab_user_id, :string)
    field(:username, :string)
    field(:name, :string)
    field(:web_url, :string)
    field(:scopes, {:array, :string}, default: [])

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(api_root encrypted_service_account_token service_account_token_set_by_identity_id service_account_token_set_at last_validated_at last_validation_error gitlab_user_id username name web_url scopes)a
  @required ~w(api_root)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(credential, attrs) do
    credential
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
