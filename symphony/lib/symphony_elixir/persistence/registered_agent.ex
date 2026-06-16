defmodule SymphonyElixir.Persistence.RegisteredAgent do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @providers ~w(codex)
  @auth_modes ~w(subscription api auth_json)
  @credential_statuses ~w(pending login_started configured failed)
  @mcp_install_statuses ~w(pending installing configured failed)
  @usage_statuses ~w(unknown available unavailable not_applicable)

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "registered_agents" do
    field(:provider, :string)
    field(:name, :string)
    field(:auth_mode, :string)
    field(:codex_home, :string)
    field(:credential_status, :string, default: "pending")
    field(:login_started_at, :utc_datetime_usec)
    field(:last_login_exit_status, :integer)
    field(:last_login_message, :string)
    field(:mcp_install_status, :string, default: "pending")
    field(:mcp_install_started_at, :utc_datetime_usec)
    field(:mcp_install_finished_at, :utc_datetime_usec)
    field(:mcp_install_exit_status, :integer)
    field(:mcp_install_message, :string)
    field(:mcp_server_names, {:array, :string}, default: [])
    field(:usage_status, :string, default: "unknown")
    field(:usage_snapshot, :map)
    field(:usage_checked_at, :utc_datetime_usec)
    field(:usage_error, :string)

    timestamps(type: :utc_datetime_usec)
  end

  @fields ~w(id provider name auth_mode codex_home credential_status login_started_at last_login_exit_status last_login_message mcp_install_status mcp_install_started_at mcp_install_finished_at mcp_install_exit_status mcp_install_message mcp_server_names usage_status usage_snapshot usage_checked_at usage_error)a
  @required ~w(provider name auth_mode codex_home credential_status)a

  @spec providers() :: [String.t()]
  def providers, do: @providers

  @spec auth_modes() :: [String.t()]
  def auth_modes, do: @auth_modes

  @spec credential_statuses() :: [String.t()]
  def credential_statuses, do: @credential_statuses

  @spec mcp_install_statuses() :: [String.t()]
  def mcp_install_statuses, do: @mcp_install_statuses

  @spec usage_statuses() :: [String.t()]
  def usage_statuses, do: @usage_statuses

  @spec changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, @fields)
    |> validate_required(@required)
    |> validate_inclusion(:provider, @providers)
    |> validate_inclusion(:auth_mode, @auth_modes)
    |> validate_inclusion(:credential_status, @credential_statuses)
    |> validate_inclusion(:mcp_install_status, @mcp_install_statuses)
    |> validate_inclusion(:usage_status, @usage_statuses)
    |> unique_constraint(:codex_home)
  end
end
