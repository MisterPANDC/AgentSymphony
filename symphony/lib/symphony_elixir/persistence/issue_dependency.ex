defmodule SymphonyElixir.Persistence.IssueDependency do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Persistence.Issue

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "issue_dependencies" do
    belongs_to(:blocked_issue, Issue)
    belongs_to(:blocking_issue, Issue)

    field(:created_by, :string, default: "local_operator")
    field(:reason, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(blocked_issue_id blocking_issue_id created_by reason)a
  @required ~w(blocked_issue_id blocking_issue_id created_by)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(edge, attrs) do
    changeset =
      edge
      |> cast(attrs, @fields)
      |> validate_required(@required)

    validate_change(changeset, :blocking_issue_id, fn :blocking_issue_id, blocking_issue_id ->
      if get_field(changeset, :blocked_issue_id) == blocking_issue_id do
        [blocking_issue_id: "cannot depend on itself"]
      else
        []
      end
    end)
  end
end
