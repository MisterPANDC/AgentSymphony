defmodule SymphonyElixir.Persistence.RuntimeBlock do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Persistence.AgentRun
  alias SymphonyElixir.Persistence.Issue

  @block_types ~w(operator_input approval_required mcp_elicitation sandbox_rejection external_failure blocked_by_dependency)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "runtime_blocks" do
    belongs_to(:issue, Issue, foreign_key: :gitlab_issue_id)
    belongs_to(:agent_run, AgentRun)

    field(:block_type, :string)
    field(:message, :string)
    field(:payload, :map, default: %{})
    field(:resolved_at, :utc_datetime_usec)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(gitlab_issue_id agent_run_id block_type message payload resolved_at)a
  @required ~w(gitlab_issue_id block_type payload)a

  @spec block_types() :: [String.t()]
  def block_types, do: @block_types

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(block, attrs) do
    block
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:block_type, @block_types)
  end
end
