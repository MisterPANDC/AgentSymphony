defmodule SymphonyElixirWeb.SyncController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.Sync.Poller

  @spec status(Conn.t(), map()) :: Conn.t()
  def status(conn, _params), do: json(conn, Poller.status())

  @spec refresh(Conn.t(), map()) :: Conn.t()
  def refresh(conn, _params) do
    case Poller.refresh() do
      {:ok, payload} -> json(conn, payload)
      {:error, reason} -> conn |> put_status(422) |> json(%{error: %{code: "sync_refresh_failed", message: inspect(reason)}})
    end
  end
end
