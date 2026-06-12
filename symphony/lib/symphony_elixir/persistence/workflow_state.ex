defmodule SymphonyElixir.Persistence.WorkflowState do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Persistence.Issue

  @statuses ~w(triage todo in_progress blocked review done canceled)
  @priorities ~w(none low medium high urgent)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "issue_workflow_states" do
    belongs_to(:issue, Issue, foreign_key: :gitlab_issue_id)

    field(:status, :string)
    field(:priority, :string, default: "none")
    field(:rank, :decimal)
    field(:claimed_by, :string)
    field(:claimed_at, :utc_datetime_usec)
    field(:last_transition_at, :utc_datetime_usec)
    field(:last_transition_reason, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(gitlab_issue_id status priority rank claimed_by claimed_at last_transition_at last_transition_reason)a
  @required ~w(gitlab_issue_id status priority)a

  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @spec priorities() :: [String.t()]
  def priorities, do: @priorities

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:priority, @priorities)
  end
end
