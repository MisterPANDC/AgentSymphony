defmodule SymphonyElixir.AiChat do
  @moduledoc """
  Project-scoped Codex chat sessions for the floating web UI.
  """

  use GenServer

  alias SymphonyElixir.Codex.AppServer
  alias SymphonyElixir.Tracker.Issue
  alias SymphonyElixir.Workspace

  @max_events 400

  defmodule Session do
    @moduledoc false
    defstruct [
      :project_id,
      :project_name,
      :workspace,
      :session,
      :task_ref,
      :status,
      next_seq: 1,
      events: [],
      pending_approvals: %{}
    ]
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @spec status(map()) :: map()
  def status(project), do: GenServer.call(__MODULE__, {:status, project})

  @spec send_message(map(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def send_message(project, text, actor) when is_binary(text) do
    GenServer.call(__MODULE__, {:send_message, project, text, actor}, 30_000)
  end

  @spec reset(map()) :: :ok
  def reset(project), do: GenServer.call(__MODULE__, {:reset, project})

  @spec resolve_approval(map(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def resolve_approval(project, request_id, decision)
      when is_binary(request_id) and is_binary(decision) do
    GenServer.call(__MODULE__, {:resolve_approval, project, request_id, decision})
  end

  @impl true
  def init(_opts), do: {:ok, %{sessions: %{}}}

  @impl true
  def handle_call({:status, project}, _from, state) do
    session = Map.get(state.sessions, project_id(project)) || new_session(project)
    {:reply, session_payload(session), put_session(state, session)}
  end

  def handle_call({:send_message, project, text, actor}, _from, state) do
    text = String.trim(text)
    session = Map.get(state.sessions, project_id(project)) || new_session(project)

    cond do
      text == "" ->
        {:reply, {:error, :empty_message}, put_session(state, session)}

      is_reference(session.task_ref) ->
        {:reply, {:error, :turn_in_progress}, put_session(state, session)}

      true ->
        case ensure_codex_session(session) do
          {:ok, session} ->
            session = append_event(session, "user_message", %{text: text, actor: actor})
            owner = self()
            project_id = session.project_id
            issue = chat_issue(project)

            task =
              Task.Supervisor.async_nolink(SymphonyElixir.TaskSupervisor, fn ->
                AppServer.run_turn(session.session, text, issue,
                  on_message: fn message -> send(owner, {:ai_chat_codex_event, project_id, message}) end,
                  approval_resolver: approval_resolver(owner, project_id)
                )
              end)

            session = %{session | task_ref: task.ref, status: "running"}
            state = put_session(state, session)
            {:reply, {:ok, session_payload(session)}, state}

          {:error, reason, session} ->
            {:reply, {:error, reason}, put_session(state, session)}
        end
    end
  end

  def handle_call({:reset, project}, _from, state) do
    project_id = project_id(project)
    state.sessions |> Map.get(project_id) |> stop_codex_session()
    state = update_in(state.sessions, &Map.delete(&1, project_id))
    {:reply, :ok, state}
  end

  def handle_call({:resolve_approval, project, request_id, decision}, _from, state) do
    project_id = project_id(project)
    session = Map.get(state.sessions, project_id)

    cond do
      not valid_decision?(decision) ->
        {:reply, {:error, :invalid_approval_decision}, state}

      is_nil(session) ->
        {:reply, {:error, :chat_not_found}, state}

      true ->
        case Map.pop(session.pending_approvals, request_id) do
          {nil, _pending_approvals} ->
            {:reply, {:error, :approval_not_found}, state}

          {pid, pending_approvals} when is_pid(pid) ->
            send(pid, {:ai_chat_approval_decision, request_id, decision})
            session = %{session | pending_approvals: pending_approvals}
            state = put_session(state, session)
            {:reply, {:ok, session_payload(session)}, state}
        end
    end
  end

  @impl true
  def handle_info({:ai_chat_codex_event, project_id, message}, state) do
    session = Map.get(state.sessions, project_id)

    if session do
      event_type = message |> Map.get(:event, :codex_event) |> to_string()
      session = append_event(session, event_type, message)
      {:noreply, put_session(state, session)}
    else
      {:noreply, state}
    end
  end

  def handle_info({ref, {:ok, _result}}, state) when is_reference(ref) do
    {:noreply, complete_task(state, ref, "idle")}
  end

  def handle_info({ref, {:error, reason}}, state) when is_reference(ref) do
    {:noreply, complete_task(state, ref, "failed", reason)}
  end

  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) when is_reference(ref) do
    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state) when is_reference(ref) do
    {:noreply, complete_task(state, ref, "failed", reason)}
  end

  def handle_info({:ai_chat_approval_waiting, project_id, request_id, pid}, state)
      when is_binary(project_id) and is_binary(request_id) and is_pid(pid) do
    case Map.get(state.sessions, project_id) do
      %Session{} = session ->
        session = %{session | pending_approvals: Map.put(session.pending_approvals, request_id, pid)}
        {:noreply, put_session(state, session)}

      nil ->
        {:noreply, state}
    end
  end

  defp ensure_codex_session(%Session{session: %{} = _session} = chat), do: {:ok, chat}

  defp ensure_codex_session(%Session{} = chat) do
    with {:ok, workspace} <- Workspace.create_for_issue(workspace_identifier(chat)),
         {:ok, session} <- AppServer.start_session(workspace) do
      chat =
        chat
        |> append_event("workspace_created", %{workspace: workspace})
        |> append_event("codex_started", %{thread_id: session.thread_id})

      {:ok, %{chat | workspace: workspace, session: session, status: "idle"}}
    else
      {:error, reason} ->
        chat = append_event(chat, "error", %{message: format_error(reason), reason: inspect(reason)})
        {:error, reason, %{chat | status: "failed"}}
    end
  end

  defp complete_task(state, ref, status, reason \\ nil) do
    {project_id, session} =
      Enum.find(state.sessions, fn {_project_id, session} -> session.task_ref == ref end) || {nil, nil}

    if session do
      session =
        session
        |> Map.merge(%{task_ref: nil, status: status})
        |> maybe_append_failure(reason)

      put_in(state.sessions[project_id], session)
    else
      state
    end
  end

  defp maybe_append_failure(session, nil), do: session
  defp maybe_append_failure(session, reason), do: append_event(session, "error", %{message: format_error(reason), reason: inspect(reason)})

  defp approval_resolver(owner, project_id) do
    fn request_id, _payload ->
      send(owner, {:ai_chat_approval_waiting, project_id, request_id, self()})

      receive do
        {:ai_chat_approval_decision, ^request_id, decision} ->
          {:ok, decision}
      after
        3_600_000 ->
          {:error, :approval_timeout}
      end
    end
  end

  defp append_event(%Session{} = session, type, payload) do
    event = %{
      id: "#{session.project_id}:#{session.next_seq}",
      seq: session.next_seq,
      type: type,
      payload: json_safe(payload || %{}),
      inserted_at: DateTime.utc_now()
    }

    events = [event | session.events] |> Enum.take(@max_events)
    %{session | events: events, next_seq: session.next_seq + 1}
  end

  defp session_payload(%Session{} = session) do
    %{
      status: session.status || "idle",
      workspace: session.workspace,
      events: session.events |> Enum.reverse() |> Enum.map(&event_payload/1)
    }
  end

  defp event_payload(event) do
    %{
      id: event.id,
      seq: event.seq,
      type: event.type,
      payload: event.payload,
      insertedAt: DateTime.to_iso8601(event.inserted_at)
    }
  end

  defp put_session(state, %Session{} = session), do: put_in(state.sessions[session.project_id], session)

  defp new_session(project) do
    %Session{
      project_id: project_id(project),
      project_name: project[:name] || project["name"] || project[:path_with_namespace] || project["path_with_namespace"],
      status: "idle"
    }
  end

  defp project_id(project), do: to_string(project[:id] || project["id"])

  defp workspace_identifier(%Session{project_id: project_id}), do: "ai-chat-#{project_id}"

  defp chat_issue(project) do
    name = project[:name] || project["name"] || project[:path_with_namespace] || project["path_with_namespace"] || "current project"

    %Issue{
      id: "ai-chat:#{project_id(project)}",
      identifier: "AI-CHAT",
      title: "AI chat for #{name}",
      description: "Interactive Codex chat opened from the Symphony web UI.",
      workflow_status: "chat",
      gitlab_state: "opened",
      labels: []
    }
  end

  defp format_error(reason) do
    case reason do
      {:invalid_workspace_cwd, _, _} -> "Codex could not start because the chat workspace is outside Symphony's configured workspace root."
      {:workspace_hook_failed, hook, status, _output} -> "Workspace hook #{hook} failed with exit status #{status}."
      {:turn_failed, details} -> "Codex turn failed: #{inspect(details)}"
      {:turn_cancelled, _details} -> "Codex turn was cancelled."
      {:turn_input_required, _payload} -> "Codex needs operator input that is not yet supported in this chat surface."
      {:approval_resolution_failed, reason} -> "Codex approval failed: #{inspect(reason)}"
      _ -> "Codex chat failed: #{inspect(reason)}"
    end
  end

  defp valid_decision?(decision), do: decision in ["accept", "acceptForSession", "decline", "cancel"]

  defp stop_codex_session(%Session{session: %{} = session}), do: AppServer.stop_session(session)
  defp stop_codex_session(_session), do: :ok

  defp json_safe(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp json_safe(%Date{} = date), do: Date.to_iso8601(date)
  defp json_safe(%Time{} = time), do: Time.to_iso8601(time)

  defp json_safe(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested} -> {json_key(key), json_safe(nested)} end)
    |> Map.new()
  end

  defp json_safe(value) when is_list(value), do: Enum.map(value, &json_safe/1)
  defp json_safe(value) when is_atom(value), do: to_string(value)
  defp json_safe(value), do: value

  defp json_key(key) when is_atom(key), do: Atom.to_string(key)
  defp json_key(key), do: key
end
