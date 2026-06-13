defmodule SymphonyElixirWeb.MonitorController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias SymphonyElixir.{Monitor.DTO, Store, Sync.Poller}
  alias SymphonyElixirWeb.AuthPlug
  alias SymphonyElixirWeb.DTO, as: WebDTO

  @spec state(Conn.t(), map()) :: Conn.t()
  def state(conn, _params), do: json(conn, DTO.state(15_000, monitor_filters(conn)))

  @spec events(Conn.t(), map()) :: Conn.t()
  def events(conn, _params) do
    json(conn, %{events: Store.list_events() |> Enum.map(&WebDTO.event/1)})
  end

  @spec blocks(Conn.t(), map()) :: Conn.t()
  def blocks(conn, _params) do
    json(conn, %{blocks: Store.list_open_runtime_blocks() |> Enum.map(&WebDTO.block/1)})
  end

  @spec resolve_block(Conn.t(), map()) :: Conn.t()
  def resolve_block(conn, %{"id" => id}) do
    case Store.resolve_runtime_block(id) do
      {:ok, block} -> json(conn, %{block: WebDTO.block(block)})
      {:error, reason} -> error(conn, 404, "block_resolve_failed", inspect(reason))
    end
  end

  @spec refresh(Conn.t(), map()) :: Conn.t()
  def refresh(conn, _params) do
    Poller.refresh()
    json(conn, DTO.state(15_000, monitor_filters(conn)))
  end

  @spec runs(Conn.t(), map()) :: Conn.t()
  def runs(conn, _params) do
    json(conn, %{runs: Store.list_runs(run_filters(conn)) |> Enum.map(&WebDTO.run/1)})
  end

  @spec run(Conn.t(), map()) :: Conn.t()
  def run(conn, %{"id" => id}) do
    case visible_run(conn, id) do
      nil -> error(conn, 404, "run_not_found", "Run not found")
      run -> json(conn, %{run: WebDTO.run(run)})
    end
  end

  @spec run_events(Conn.t(), map()) :: Conn.t()
  def run_events(conn, %{"id" => id}) do
    case visible_run(conn, id) do
      nil -> error(conn, 404, "run_not_found", "Run not found")
      _run -> json(conn, %{events: Store.list_run_events(id)})
    end
  end

  @spec cancel_run(Conn.t(), map()) :: Conn.t()
  def cancel_run(conn, %{"id" => id}) do
    case visible_run(conn, id) && Store.update_run(id, %{status: "canceled", finished_at: DateTime.utc_now(), exit_reason: "canceled by operator"}) do
      {:ok, run} ->
        Store.add_run_event(id, "canceled", "Run canceled by operator", %{actor: AuthPlug.actor(conn)})
        json(conn, %{run: WebDTO.run(run)})

      {:error, reason} ->
        error(conn, 404, "run_cancel_failed", inspect(reason))

      nil ->
        error(conn, 404, "run_not_found", "Run not found")
    end
  end

  defp monitor_filters(conn) do
    case current_project_setting_id(conn) do
      nil -> []
      project_id -> [project_setting_id: project_id, project: AuthPlug.current_project(conn)]
    end
  end

  defp run_filters(conn) do
    case current_project_setting_id(conn) do
      nil -> []
      project_id -> [project_setting_id: project_id]
    end
  end

  defp visible_run(conn, id) do
    case {Store.get_run(id), current_project_setting_id(conn)} do
      {nil, _project_id} -> nil
      {%{} = run, nil} -> run
      {%{issue: %{gitlab_project_setting_id: project_id}} = run, project_id} -> run
      _ -> nil
    end
  end

  defp current_project_setting_id(conn) do
    case AuthPlug.current_user(conn) do
      %{local?: true} -> nil
      %{project_setting_id: project_setting_id} -> project_setting_id
      _ -> nil
    end
  end

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
