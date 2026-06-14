defmodule SymphonyElixirWeb.WorkflowTransition do
  @moduledoc false

  alias SymphonyElixir.Orchestrator
  alias SymphonyElixir.Store
  alias SymphonyElixir.Workflow.Transitions

  @spec require_active_run_stop_confirmation(map(), String.t(), map()) :: :ok | {:error, :active_run_stop_confirmation_required}
  def require_active_run_stop_confirmation(issue, status, params) do
    if stops_active_run?(issue, status) and not confirmed?(params) do
      {:error, :active_run_stop_confirmation_required}
    else
      :ok
    end
  end

  @spec maybe_stop_active_run(map(), String.t(), String.t()) :: :ok | {:error, term()}
  def maybe_stop_active_run(issue, status, actor) do
    if stops_active_run?(issue, status) do
      stop_active_run(issue, status, actor)
    else
      :ok
    end
  end

  @spec stops_active_run?(map(), String.t()) :: boolean()
  def stops_active_run?(issue, status) do
    active_run_id = Map.get(issue, :active_run_id) || Map.get(issue, "active_run_id")
    is_binary(active_run_id) and not Transitions.dispatch_candidate?(status)
  end

  defp stop_active_run(issue, status, actor) do
    run_id = Map.get(issue, :active_run_id) || Map.get(issue, "active_run_id")
    now = DateTime.utc_now()
    status = Transitions.normalize(status)

    case Store.update_run(run_id, %{
           status: "canceled",
           finished_at: now,
           last_heartbeat_at: now,
           exit_reason: "canceled by workflow status change to #{status}"
         }) do
      {:ok, _run} ->
        Store.add_run_event(run_id, "canceled", "Run canceled by workflow status change to #{status}", %{actor: actor})
        Orchestrator.request_refresh()
        :ok

      {:error, reason} ->
        {:error, {:active_run_cancel_failed, reason}}
    end
  end

  defp confirmed?(params) do
    Map.get(params, "confirmStopRun") in [true, "true"] or
      Map.get(params, :confirm_stop_run) in [true, "true"] or
      Map.get(params, "confirm_stop_run") in [true, "true"]
  end
end
