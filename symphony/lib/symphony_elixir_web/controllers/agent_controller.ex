defmodule SymphonyElixirWeb.AgentController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.Orchestrator

  @spec dispatch(Conn.t(), map()) :: Conn.t()
  def dispatch(conn, _params) do
    json(conn, %{dispatch: Orchestrator.request_refresh()})
  end
end
