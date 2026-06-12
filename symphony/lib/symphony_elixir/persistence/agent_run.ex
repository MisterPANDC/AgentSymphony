defmodule SymphonyElixir.Persistence.AgentRun do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Persistence.Issue

  @statuses ~w(queued starting running blocked succeeded failed canceled stale)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_runs" do
    belongs_to(:issue, Issue, foreign_key: :gitlab_issue_id)

    field(:run_number, :integer)
    field(:status, :string)
    field(:mode, :string, default: "workflow")
    field(:workspace_path, :string)
    field(:codex_thread_id, :string)
    field(:started_at, :utc_datetime_usec)
    field(:finished_at, :utc_datetime_usec)
    field(:last_heartbeat_at, :utc_datetime_usec)
    field(:exit_reason, :string)
    field(:error_message, :string)
    field(:blocked_reason, :string)
    field(:needs_operator_input, :boolean, default: false)
    field(:summary, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(gitlab_issue_id run_number status mode workspace_path codex_thread_id started_at finished_at last_heartbeat_at exit_reason error_message blocked_reason needs_operator_input summary)a
  @required ~w(gitlab_issue_id run_number status mode needs_operator_input)a

  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(run, attrs) do
    run
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:status, @statuses)
  end
end
