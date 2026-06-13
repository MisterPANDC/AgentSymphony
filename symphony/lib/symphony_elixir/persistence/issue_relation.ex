defmodule SymphonyElixir.Persistence.IssueRelation do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Persistence.Issue

  @relation_types ~w(relates_to)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "issue_relations" do
    belongs_to(:source_issue, Issue)
    belongs_to(:target_issue, Issue)

    field(:relation_type, :string)
    field(:created_by, :string, default: "local_operator")
    field(:reason, :string)
    field(:metadata, :map, default: %{})

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(source_issue_id target_issue_id relation_type created_by reason metadata)a
  @required ~w(source_issue_id target_issue_id relation_type created_by metadata)a

  @spec relation_types() :: [String.t()]
  def relation_types, do: @relation_types

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(relation, attrs) do
    changeset =
      relation
      |> cast(attrs, @fields)
      |> validate_required(@required)
      |> validate_inclusion(:relation_type, @relation_types)

    validate_change(changeset, :target_issue_id, fn :target_issue_id, target_issue_id ->
      if get_field(changeset, :source_issue_id) == target_issue_id do
        [target_issue_id: "cannot relate to itself"]
      else
        []
      end
    end)
  end
end
