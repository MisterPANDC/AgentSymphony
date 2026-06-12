defmodule SymphonyElixir.Persistence.AgentRunEvent do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias SymphonyElixir.Persistence.AgentRun

  @event_types ~w(queued workspace_created codex_started turn_started turn_finished comment_posted status_changed blocked operator_input_required succeeded failed canceled heartbeat)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "agent_run_events" do
    belongs_to(:agent_run, AgentRun)

    field(:event_type, :string)
    field(:message, :string)
    field(:payload, :map, default: %{})

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @fields ~w(agent_run_id event_type message payload)a
  @required ~w(agent_run_id event_type payload)a

  @spec event_types() :: [String.t()]
  def event_types, do: @event_types

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:event_type, @event_types)
  end
end
