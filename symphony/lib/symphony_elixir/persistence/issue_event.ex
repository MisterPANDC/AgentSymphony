defmodule SymphonyElixir.Persistence.IssueEvent do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @sources ~w(gitlab_sync local_ui agent system)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "issue_events" do
    field(:gitlab_issue_id, :binary_id)
    field(:event_type, :string)
    field(:source, :string)
    field(:actor, :string)
    field(:payload, :map, default: %{})
    field(:run_id, :binary_id)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  @fields ~w(gitlab_issue_id event_type source actor payload run_id)a
  @required ~w(event_type source payload)a

  @spec sources() :: [String.t()]
  def sources, do: @sources

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(event, attrs) do
    event
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:source, @sources)
  end
end
