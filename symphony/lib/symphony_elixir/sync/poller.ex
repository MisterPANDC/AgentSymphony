defmodule SymphonyElixir.Sync.Poller do
  @moduledoc """
  Polling-only GitLab issue and note sync.
  """

  use GenServer
  require Logger

  alias Symphony.GitLab.{Client, Config, IssueMapper, NoteMapper}
  alias SymphonyElixir.GitLab.IssueLifecycle
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

  @spec reset_issue_cursor(String.t() | nil) :: :ok
  def reset_issue_cursor(project_setting_id \\ nil)

  def reset_issue_cursor(project_setting_id) when is_binary(project_setting_id) do
    reset_cursor(issue_cursor_name(project_setting_id))
    :ok
  end

  def reset_issue_cursor(_project_setting_id) do
    reset_cursor(@issue_cursor)

    Store.projects()
    |> Enum.each(fn
      %{id: project_setting_id} when is_binary(project_setting_id) -> reset_cursor(issue_cursor_name(project_setting_id))
      _project -> :ok
    end)

    :ok
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
    case Store.projects() do
      [] -> {:error, :project_not_selected}
      projects -> sync_projects(projects)
    end
  end

  defp sync_projects(projects) do
    configured = Enum.filter(projects, &(&1.project_access_token_status == "configured"))

    if configured == [] do
      put_error_cursor(@issue_cursor, :project_access_token_missing)
      {:error, :project_access_token_missing}
    else
      results = Enum.map(configured, &sync_project/1)

      errors =
        results
        |> Enum.filter(&match?({:error, _}, &1))
        |> Enum.map(fn {:error, reason} -> reason end)

      if errors == [] do
        summaries = Enum.map(results, fn {:ok, summary} -> summary end)

        {:ok,
         %{
           projects: summaries,
           issue_count: Enum.sum(Enum.map(summaries, & &1.issue_count)),
           backfilled_issue_count: Enum.sum(Enum.map(summaries, &Map.get(&1, :backfilled_issue_count, 0)))
         }}
      else
        put_error_cursor(@issue_cursor, hd(errors))
        {:error, {:project_sync_failed, errors}}
      end
    end
  end

  defp sync_project(project) do
    cursor_name = issue_cursor_name(project.id)

    with {:ok, token} <- Store.project_access_token(project.id),
         {:ok, config} <- Config.from_project_setting(project, token),
         :ok <- Client.validate_api_root(config),
         {:ok, raw_project} <- Client.get_project(config, auth: {:private_token, token}),
         project_setting <- upsert_project(config, raw_project),
         backfilled_issue_count = Store.backfill_issue_project_setting(project_setting),
         {:ok, issues} <- sync_issues(config, project_setting),
         :ok <- put_success_cursor(cursor_name, DateTime.utc_now()) do
      Store.record_event("sync_project_validated", "gitlab_sync", %{project_id: raw_project["id"]})

      {:ok,
       %{
         project_id: project_setting.project_id,
         issue_count: length(issues),
         backfilled_issue_count: backfilled_issue_count
       }}
    else
      {:error, reason} ->
        put_error_cursor(cursor_name, reason)
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

  defp sync_issues(config, project_setting) do
    params =
      %{
        state: "all",
        order_by: "updated_at",
        sort: "asc",
        per_page: config.sync_page_size
      }
      |> maybe_put_updated_after(config, project_setting)

    with {:ok, raw_issues} <- Client.list_project_issues(config, params) do
      existing_by_iid =
        project_setting.id
        |> local_project_issues_by_iid()

      issues = Enum.map(raw_issues, &sync_issue(config, project_setting, existing_by_iid, &1))

      {:ok, issues}
    end
  end

  defp sync_issue(config, project_setting, existing_by_iid, raw) do
    attrs =
      raw
      |> IssueMapper.from_gitlab()
      |> Map.put(:gitlab_project_setting_id, project_setting.id)

    previous = Map.get(existing_by_iid, attrs.iid)
    issue = Store.upsert_issue(attrs)

    if IssueLifecycle.external_reopen?(previous, issue) do
      restore_externally_reopened_issue(config, issue)
    else
      issue
    end
  end

  defp restore_externally_reopened_issue(config, issue) do
    case Store.transition_workflow(issue.id, "triage",
           source: "gitlab_sync",
           actor: "gitlab_sync",
           reason: "GitLab issue reopened"
         ) do
      {:ok, _workflow} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to restore externally reopened issue workflow: issue_id=#{issue.id} reason=#{inspect(reason)}")
    end

    issue = Store.get_issue(issue.id) || issue
    ensure_reopened_label(config, issue)
  end

  defp ensure_reopened_label(config, issue) do
    case IssueLifecycle.reopen_attrs(issue) do
      :noop ->
        issue

      attrs ->
        case Client.update_project_issue(config, issue.iid, attrs) do
          {:ok, raw_issue} ->
            raw_issue
            |> IssueMapper.from_gitlab()
            |> Map.put(:gitlab_project_setting_id, issue.gitlab_project_setting_id)
            |> Store.upsert_issue()

          {:error, reason} ->
            Logger.warning("Failed to add reopened label to GitLab issue: issue_id=#{issue.id} reason=#{inspect(reason)}")
            issue
        end
    end
  end

  defp local_project_issues_by_iid(project_setting_id) do
    Store.list_issues(project_setting_id: project_setting_id)
    |> Map.new(&{&1.iid, &1})
  end

  defp maybe_put_updated_after(params, config, project_setting) do
    case issue_last_success_at(project_setting) do
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
    with %{} = issue <- Store.get_issue(issue_id),
         {:ok, config} <- config_for_issue(issue),
         {:ok, raw_notes} <- Client.list_issue_notes(config, issue.iid, %{per_page: config.sync_page_size}, auth: {:private_token, config.token}) do
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

  defp config_for_issue(issue) do
    with project_id when is_binary(project_id) <- Map.get(issue, :gitlab_project_setting_id),
         %{} = project <- Store.project_by_id(project_id),
         {:ok, token} <- Store.project_access_token(project.id) do
      Config.from_project_setting(project, token)
    else
      nil -> {:error, :project_not_found}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :project_access_token_missing}
    end
  end

  defp issue_last_success_at(project_setting) do
    Store.cursors()
    |> Map.get(cursor_key(issue_cursor_name(project_setting.id)))
    |> case do
      %{last_success_at: %DateTime{} = datetime} -> datetime
      _ -> nil
    end
  end

  defp reset_cursor(cursor_name) do
    Store.put_cursor("gitlab", cursor_name, %{
      cursor_value: nil,
      last_success_at: nil,
      last_attempt_at: nil,
      last_error: nil,
      last_error_at: nil
    })
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

  defp issue_cursor_name(project_setting_id) when is_binary(project_setting_id), do: "#{@issue_cursor}:#{project_setting_id}"

  defp cursor_key(cursor_name), do: "gitlab:#{cursor_name}"

  defp schedule(state, delay_ms) do
    if is_reference(state.timer_ref), do: Process.cancel_timer(state.timer_ref)
    timer_ref = Process.send_after(self(), :sync, delay_ms)
    %{state | timer_ref: timer_ref, next_run_at: DateTime.utc_now() |> DateTime.add(div(delay_ms, 1000), :second)}
  end

  defp interval_ms do
    case System.get_env("SYMPHONY_SYNC_INTERVAL_MS") do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int > 0 -> int
          _ -> 60_000
        end

      _ ->
        60_000
    end
  end
end
