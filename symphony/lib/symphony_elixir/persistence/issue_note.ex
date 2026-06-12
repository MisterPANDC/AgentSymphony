defmodule SymphonyElixir.Persistence.IssueNote do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Persistence.Issue

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "gitlab_issue_notes" do
    belongs_to(:issue, Issue, foreign_key: :gitlab_issue_id)

    field(:note_id, :integer)
    field(:body, :string)
    field(:author, :map)
    field(:system, :boolean, default: false)
    field(:internal, :boolean, default: false)
    field(:resolvable, :boolean, default: false)
    field(:gitlab_created_at, :utc_datetime_usec)
    field(:gitlab_updated_at, :utc_datetime_usec)
    field(:raw_gitlab, :map)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(gitlab_issue_id note_id body author system internal resolvable gitlab_created_at gitlab_updated_at raw_gitlab)a
  @required ~w(gitlab_issue_id note_id body system internal resolvable)a

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(note, attrs) do
    note
    |> cast(attrs, @fields)
    |> validate_required(@required)
  end
end
