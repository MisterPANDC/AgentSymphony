defmodule SymphonyElixirWeb.RunController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.Store
  alias SymphonyElixirWeb.DTO

  @spec index(Conn.t(), map()) :: Conn.t()
  def index(conn, _params) do
    json(conn, %{runs: Store.list_runs() |> Enum.map(&DTO.run/1)})
  end

  @spec show(Conn.t(), map()) :: Conn.t()
  def show(conn, %{"id" => id}) do
    case Store.get_run(id) do
      nil -> error(conn, 404, "run_not_found", "Run not found")
      run -> json(conn, %{run: DTO.run(run)})
    end
  end

  @spec events(Conn.t(), map()) :: Conn.t()
  def events(conn, %{"id" => id}) do
    case Store.get_run(id) do
      nil -> error(conn, 404, "run_not_found", "Run not found")
      _run -> json(conn, %{events: Store.list_run_events(id)})
    end
  end

  @spec cancel(Conn.t(), map()) :: Conn.t()
  def cancel(conn, %{"id" => id}) do
    case Store.update_run(id, %{status: "canceled", finished_at: DateTime.utc_now(), exit_reason: "canceled by operator"}) do
      {:ok, run} ->
        Store.add_run_event(id, "canceled", "Run canceled by operator", %{})
        json(conn, %{run: DTO.run(Store.get_run(run.id))})

      {:error, reason} ->
        error(conn, 404, "run_cancel_failed", inspect(reason))
    end
  end

  @spec retry(Conn.t(), map()) :: Conn.t()
  def retry(conn, %{"id" => id}) do
    case Store.get_run(id) do
      nil ->
        error(conn, 404, "run_not_found", "Run not found")

      run ->
        {:ok, retry} = Store.create_run(run.gitlab_issue_id, %{status: "queued", mode: "retry"})
        Store.add_run_event(retry.id, "queued", "Retry queued by operator", %{previous_run_id: id})
        json(conn, %{run: DTO.run(Store.get_run(retry.id))})
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
