defmodule SymphonyElixir.Persistence.SyncCursor do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sync_cursors" do
    field(:source, :string)
    field(:cursor_name, :string)
    field(:cursor_value, :string)
    field(:last_success_at, :utc_datetime_usec)
    field(:last_attempt_at, :utc_datetime_usec)
    field(:last_error, :string)
    field(:last_error_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(source cursor_name cursor_value last_success_at last_attempt_at last_error last_error_at)a
  @required ~w(source cursor_name)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(cursor, attrs) do
    cursor
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
