defmodule SymphonyElixir.Sync.Poller do
  @moduledoc """
  Polling-only GitLab issue and note sync.
  """

  use GenServer
  require Logger

  alias Symphony.GitLab.{Client, Config, IssueMapper, NoteMapper}
  alias SymphonyElixir.{StatusDashboard, Store}

  @issue_cursor "gitlab_issues_updated_after"
  @notes_cursor "gitlab_notes_last_full_sync_at"

  defstruct [
    :timer_ref,
    :next_run_at,
    pending: false,
    last_error: nil
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec refresh() :: {:ok, map()} | {:error, term()}
  def refresh do
    GenServer.call(__MODULE__, :refresh, 60_000)
  end

  @spec status() :: map()
  def status do
    GenServer.call(__MODULE__, :status)
  end

  @impl true
  def init(_opts) do
    state = schedule(%__MODULE__{}, 0)
    {:ok, state}
  end

  @impl true
  def handle_info(:sync, state) do
    state = %{state | timer_ref: nil, pending: true, next_run_at: nil}
    StatusDashboard.notify_update()

    state =
      case run_sync() do
        {:ok, summary} ->
          Store.record_event("sync_finished", "gitlab_sync", summary)
          %{state | pending: false, last_error: nil}

        {:error, reason} ->
          message = inspect(reason)
          Store.record_event("sync_failed", "gitlab_sync", %{error: message})
          Logger.warning("GitLab sync failed: #{message}")
          %{state | pending: false, last_error: message}
      end

    StatusDashboard.notify_update()
    {:noreply, schedule(state, interval_ms())}
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    state = schedule(%{state | pending: true}, 0)
    {:reply, {:ok, %{queued: true, next_run_at: state.next_run_at}}, state}
  end

  def handle_call(:status, _from, state) do
    cursors = Store.cursors()

    {:reply,
     %{
       pending: state.pending,
       next_run_at: state.next_run_at,
       last_error: state.last_error,
       cursors: cursors
     }, state}
  end

  defp run_sync do
    with {:ok, config} <- Config.load(),
         :ok <- Client.validate_api_root(config),
         {:ok, project} <- Client.get_project(config),
         project_setting <- upsert_project(config, project),
         {:ok, issues} <- sync_issues(config),
         :ok <- put_success_cursor(@issue_cursor, DateTime.utc_now()) do
      Store.record_event("sync_project_validated", "gitlab_sync", %{project_id: project["id"]})
      {:ok, %{project_id: project_setting.project_id, issue_count: length(issues)}}
    else
      {:error, reason} ->
        put_error_cursor(@issue_cursor, reason)
        {:error, reason}
    end
  end

  defp upsert_project(config, project) do
    Store.upsert_project(%{
      api_root: config.gitlab_api_root,
      project_ref: config.gitlab_project_ref,
      project_id: project["id"],
      path_with_namespace: project["path_with_namespace"],
      name: project["name"],
      web_url: project["web_url"],
      visibility: project["visibility"],
      last_validated_at: DateTime.utc_now(),
      last_validation_error: nil,
      read_only: false
    })
  end

  defp sync_issues(config) do
    params =
      %{
        state: "all",
        order_by: "updated_at",
        sort: "asc",
        per_page: config.sync_page_size
      }
      |> maybe_put_updated_after(config)

    with {:ok, raw_issues} <- Client.list_project_issues(config, params) do
      issues =
        Enum.map(raw_issues, fn raw ->
          raw
          |> IssueMapper.from_gitlab()
          |> Store.upsert_issue()
        end)

      {:ok, issues}
    end
  end

  defp maybe_put_updated_after(params, config) do
    case issue_last_success_at() do
      %DateTime{} = last_success ->
        updated_after =
          last_success
          |> DateTime.add(-config.sync_cursor_overlap_seconds, :second)
          |> DateTime.to_iso8601()

        Map.put(params, :updated_after, updated_after)

      _ ->
        params
    end
  end

  @spec sync_issue_notes(String.t()) :: {:ok, [map()]} | {:error, term()}
  def sync_issue_notes(issue_id) when is_binary(issue_id) do
    with {:ok, config} <- Config.load(),
         %{} = issue <- Store.get_issue(issue_id),
         {:ok, raw_notes} <- Client.list_issue_notes(config, issue.iid, per_page: config.sync_page_size) do
      notes =
        Enum.map(raw_notes, fn raw ->
          Store.upsert_note(issue_id, NoteMapper.from_gitlab(raw))
        end)

      put_success_cursor(@notes_cursor, DateTime.utc_now())
      {:ok, notes}
    else
      nil -> {:error, :issue_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp issue_last_success_at do
    Store.cursors()
    |> Map.get(cursor_key(@issue_cursor))
    |> case do
      %{last_success_at: %DateTime{} = datetime} -> datetime
      _ -> nil
    end
  end

  defp put_success_cursor(cursor_name, datetime) do
    Store.put_cursor("gitlab", cursor_name, %{
      cursor_value: DateTime.to_iso8601(datetime),
      last_success_at: datetime,
      last_attempt_at: datetime,
      last_error: nil,
      last_error_at: nil
    })

    :ok
  end

  defp put_error_cursor(cursor_name, reason) do
    now = DateTime.utc_now()

    Store.put_cursor("gitlab", cursor_name, %{
      last_attempt_at: now,
      last_error: inspect(reason),
      last_error_at: now
    })
  end

  defp cursor_key(cursor_name), do: "gitlab:#{cursor_name}"

  defp schedule(state, delay_ms) do
    if is_reference(state.timer_ref), do: Process.cancel_timer(state.timer_ref)
    timer_ref = Process.send_after(self(), :sync, delay_ms)
    %{state | timer_ref: timer_ref, next_run_at: DateTime.utc_now() |> DateTime.add(div(delay_ms, 1000), :second)}
  end

  defp interval_ms do
    case Config.load() do
      {:ok, config} -> config.sync_interval_ms
      _ -> 60_000
    end
  end
end
