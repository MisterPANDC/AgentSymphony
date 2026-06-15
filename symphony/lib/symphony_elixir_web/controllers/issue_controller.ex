defmodule SymphonyElixirWeb.IssueController do
  use Phoenix.Controller, formats: [:json]

  alias Plug.Conn
  alias Plug.Upload
  alias Symphony.GitLab.{Client, IssueMapper, NoteMapper}
  alias Symphony.GitLab.Error, as: GitLabError
  alias Symphony.GitLab.Config, as: GitLabConfig
  alias SymphonyElixir.GitLab.IssueLifecycle
  alias SymphonyElixir.Store
  alias SymphonyElixirWeb.AuthPlug
  alias SymphonyElixirWeb.DTO
  alias SymphonyElixirWeb.WorkflowTransition

  @create_workflow_paths %{
    "triage" => [],
    "todo" => ["todo"]
  }
  @create_workflow_statuses Map.keys(@create_workflow_paths)
  @upload_markdown_re ~r/(!?)\[([^\]]*)\]\(\/uploads\/([0-9a-fA-F]{32})\/([^)]+)\)/

  @spec index(Conn.t(), map()) :: Conn.t()
  def index(conn, params) do
    case current_project_setting_id(conn) do
      nil ->
        json(conn, %{issues: []})

      project_setting_id ->
        filters =
          []
          |> maybe_filter(:status, params["status"])
          |> maybe_filter(:gitlab_state, params["gitlab_state"])
          |> maybe_filter(:search, params["q"])
          |> maybe_filter(:project_setting_id, project_setting_id)

        json(conn, %{issues: Store.list_issues(filters) |> Enum.map(&DTO.issue/1)})
    end
  end

  @spec create(Conn.t(), map()) :: Conn.t()
  def create(conn, params) do
    with {:ok, attrs, workflow_status} <- create_issue_attrs(params),
         {:ok, config, auth_opts} <- current_project_gitlab_context(conn),
         {:ok, raw_issue} <- Client.create_project_issue(config, attrs, auth_opts),
         {:ok, issue} <- persist_created_issue(conn, raw_issue, workflow_status) do
      conn |> put_status(:created) |> json(%{issue: DTO.issue(issue)})
    else
      {:error, {:validation, code, message}} -> error(conn, 400, code, message)
      {:error, :project_not_selected} -> error(conn, 400, "project_not_selected", "Select a GitLab project before creating issues")
      {:error, {:workflow_status_failed, reason}} -> error(conn, 422, "workflow_status_failed", inspect(reason))
      {:error, reason} -> error(conn, 422, "issue_create_failed", inspect(reason))
    end
  end

  @spec show(Conn.t(), map()) :: Conn.t()
  def show(conn, %{"id" => id}) do
    case find_issue(conn, id) do
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      issue -> json(conn, %{issue: DTO.issue(issue)})
    end
  end

  @spec notes(Conn.t(), map()) :: Conn.t()
  def notes(conn, %{"id" => id}) do
    with %{} = issue <- find_issue(conn, id),
         {:ok, _notes} <- sync_issue_notes(conn, issue) do
      json(conn, %{notes: Store.list_notes(issue.id)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "note_sync_failed", inspect(reason))
    end
  end

  @spec create_note(Conn.t(), map()) :: Conn.t()
  def create_note(conn, %{"id" => id} = params) do
    body = Map.get(params, "body", "")

    with %{} = issue <- find_issue(conn, id),
         :ok <- validate_note_body(body),
         {:ok, files} <- upload_files(params),
         :ok <- validate_note_payload(body, files),
         :ok <- create_user_note(conn, issue, body, files) do
      json(conn, %{notes: Store.list_notes(issue.id)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, {:validation, code, message}} -> error(conn, 400, code, message)
      {:error, reason} -> error(conn, 422, "note_create_failed", inspect(reason))
    end
  end

  def create_note(conn, _params), do: error(conn, 400, "missing_body", "Note body is required")

  @spec upload(Conn.t(), map()) :: Conn.t()
  def upload(conn, %{"id" => id, "secret" => secret, "filename" => filename}) do
    with %{} = issue <- find_issue(conn, id),
         {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
         {:ok, _notes} <- sync_issue_notes(conn, issue),
         :ok <- require_upload_reference(issue, secret, filename),
         {:ok, upload} <- Client.download_project_upload(config, secret, filename, auth_opts) do
      conn
      |> put_resp_content_type(base_content_type(upload.content_type))
      |> put_resp_header("content-disposition", ~s(inline; filename="#{safe_header_filename(upload.filename)}"))
      |> send_resp(200, upload.body)
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, %GitLabError{type: :not_found}} -> error(conn, 404, "upload_not_found", "Upload not found")
      {:error, :upload_not_referenced} -> error(conn, 404, "upload_not_found", "Upload not found")
      {:error, reason} -> error(conn, 422, "upload_proxy_failed", inspect(reason))
    end
  end

  @spec update_gitlab(Conn.t(), map()) :: Conn.t()
  def update_gitlab(conn, %{"id" => id} = params) do
    attrs = Map.take(params, ["title", "description", "labels", "state_event", "due_date"])

    with %{} = issue <- find_issue(conn, id),
         {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
         {:ok, raw} <- Client.update_project_issue(config, issue.iid, attrs, auth_opts) do
      updated = raw |> IssueMapper.from_gitlab() |> Store.upsert_issue()
      json(conn, %{issue: DTO.issue(updated)})
    else
      nil -> error(conn, 404, "issue_not_found", "Issue not found")
      {:error, reason} -> error(conn, 422, "gitlab_update_failed", inspect(reason))
    end
  end

  @spec update_workflow(Conn.t(), map()) :: Conn.t()
  def update_workflow(conn, %{"id" => id, "status" => status} = params) do
    actor = AuthPlug.actor(conn)

    with %{} = issue <- find_issue(conn, id),
         :ok <- WorkflowTransition.require_active_run_stop_confirmation(issue, status, params),
         {:ok, _workflow} <-
           Store.transition_workflow(issue.id, status,
             source: "user_ui",
             actor: actor,
             reason: params["reason"]
           ),
         :ok <- WorkflowTransition.maybe_stop_active_run(issue, status, actor),
         :ok <- sync_gitlab_lifecycle(conn, issue, status),
         %{} = updated <- Store.get_issue(issue.id) do
      json(conn, %{issue: DTO.issue(updated)})
    else
      nil ->
        error(conn, 404, "issue_not_found", "Issue not found")

      {:error, :active_run_stop_confirmation_required} ->
        error(conn, 409, "active_run_stop_confirmation_required", "Changing to this status will stop the running agent. Confirm the transition to continue.")

      {:error, reason} ->
        error(conn, 422, "workflow_update_failed", inspect(reason))
    end
  end

  def update_workflow(conn, _params), do: error(conn, 400, "missing_status", "Workflow status is required")

  @spec events(Conn.t(), map()) :: Conn.t()
  def events(conn, %{"id" => id}) do
    case find_issue(conn, id) do
      nil ->
        error(conn, 404, "issue_not_found", "Issue not found")

      issue ->
        json(conn, %{events: Store.list_events(issue_id: issue.id) |> Enum.map(&DTO.event/1)})
    end
  end

  defp find_issue(conn, id) do
    case current_project_setting_id(conn) do
      nil ->
        nil

      project_id ->
        Store.list_issues(project_setting_id: project_id)
        |> Enum.find(&issue_matches?(&1, id))
    end
  end

  defp issue_matches?(issue, id) do
    issue.id == id or to_string(issue.iid) == to_string(id) or issue.identifier == id
  end

  defp maybe_filter(filters, _key, nil), do: filters
  defp maybe_filter(filters, _key, ""), do: filters
  defp maybe_filter(filters, key, value), do: [{key, value} | filters]

  defp create_issue_attrs(params) do
    with {:ok, title} <- required_string(param(params, "title"), "missing_title", "Issue title is required"),
         {:ok, workflow_status} <- create_workflow_status(param(params, "workflowStatus") || param(params, "workflow_status")),
         {:ok, labels} <- labels_value(param(params, "labels")),
         {:ok, assignee_ids} <- int_list_value(param(params, "assigneeIds") || param(params, "assignee_ids")),
         {:ok, milestone_id} <- int_value(param(params, "milestoneId") || param(params, "milestone_id")),
         {:ok, due_date} <- due_date_value(param(params, "dueDate") || param(params, "due_date")),
         {:ok, confidential} <- boolean_value(param(params, "confidential")) do
      attrs =
        %{"title" => title}
        |> maybe_put("description", optional_text(param(params, "description")) || "")
        |> maybe_put("labels", labels)
        |> maybe_put("assignee_ids", assignee_ids)
        |> maybe_put("milestone_id", milestone_id)
        |> maybe_put("due_date", due_date)
        |> maybe_put("confidential", confidential)

      {:ok, attrs, workflow_status}
    end
  end

  defp param(params, key) when is_map(params), do: Map.get(params, key) || Map.get(params, String.to_atom(key))

  defp required_string(value, code, message) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, {:validation, code, message}}
      trimmed -> {:ok, trimmed}
    end
  end

  defp required_string(_value, code, message), do: {:error, {:validation, code, message}}

  defp optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_text(_value), do: nil

  defp create_workflow_status(nil), do: {:ok, "triage"}

  defp create_workflow_status(status) when is_binary(status) do
    normalized = status |> String.trim() |> String.downcase() |> String.replace("-", "_")

    if normalized in @create_workflow_statuses do
      {:ok, normalized}
    else
      {:error, {:validation, "invalid_workflow_status", "Workflow status cannot be selected when creating issues"}}
    end
  end

  defp create_workflow_status(_status), do: {:error, {:validation, "invalid_workflow_status", "Workflow status cannot be selected when creating issues"}}

  defp labels_value(nil), do: {:ok, nil}

  defp labels_value(value) when is_binary(value) do
    labels =
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {:ok, empty_to_nil(Enum.join(labels, ","))}
  end

  defp labels_value(value) when is_list(value) do
    labels =
      value
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    {:ok, empty_to_nil(Enum.join(labels, ","))}
  end

  defp labels_value(_value), do: {:error, {:validation, "invalid_labels", "Labels must be a comma-separated string or list"}}

  defp int_list_value(nil), do: {:ok, nil}

  defp int_list_value(values) when is_list(values) do
    values
    |> Enum.reduce_while([], fn value, acc ->
      case parse_int(value) do
        nil -> {:halt, :error}
        int -> {:cont, [int | acc]}
      end
    end)
    |> case do
      :error -> {:error, {:validation, "invalid_assignee_ids", "Assignee IDs must be integers"}}
      [] -> {:ok, nil}
      ids -> {:ok, Enum.reverse(ids)}
    end
  end

  defp int_list_value(_values), do: {:error, {:validation, "invalid_assignee_ids", "Assignee IDs must be integers"}}

  defp int_value(nil), do: {:ok, nil}
  defp int_value(""), do: {:ok, nil}

  defp int_value(value) do
    case parse_int(value) do
      nil -> {:error, {:validation, "invalid_milestone_id", "Milestone ID must be an integer"}}
      int -> {:ok, int}
    end
  end

  defp due_date_value(nil), do: {:ok, nil}
  defp due_date_value(""), do: {:ok, nil}

  defp due_date_value(value) when is_binary(value) do
    trimmed = String.trim(value)

    case Date.from_iso8601(trimmed) do
      {:ok, _date} -> {:ok, trimmed}
      {:error, _reason} -> {:error, {:validation, "invalid_due_date", "Due date must be YYYY-MM-DD"}}
    end
  end

  defp due_date_value(_value), do: {:error, {:validation, "invalid_due_date", "Due date must be YYYY-MM-DD"}}

  defp boolean_value(nil), do: {:ok, nil}
  defp boolean_value(value) when is_boolean(value), do: {:ok, value}
  defp boolean_value(_value), do: {:error, {:validation, "invalid_confidential", "Confidential must be true or false"}}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp current_project_gitlab_context(conn) do
    with {:ok, access_token} <- AuthPlug.oauth_access_token(conn),
         %{} = project <- AuthPlug.current_project(conn),
         {:ok, config} <- GitLabConfig.from_project_setting(project) do
      {:ok, config, [auth: {:bearer, access_token}]}
    else
      nil -> {:error, :project_not_selected}
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_created_issue(conn, raw_issue, workflow_status) do
    issue = raw_issue |> IssueMapper.from_gitlab() |> Store.upsert_issue()

    with :ok <- set_created_workflow_status(conn, issue.id, workflow_status),
         %{} = updated <- Store.get_issue(issue.id),
         :ok <- sync_gitlab_lifecycle(conn, updated, workflow_status),
         %{} = final_issue <- Store.get_issue(issue.id) do
      {:ok, final_issue}
    else
      nil -> {:error, {:workflow_status_failed, :issue_not_found}}
      {:error, reason} -> {:error, {:workflow_status_failed, reason}}
    end
  end

  defp set_created_workflow_status(conn, issue_id, workflow_status) do
    @create_workflow_paths
    |> Map.fetch!(workflow_status)
    |> Enum.reduce_while(:ok, fn status, :ok ->
      case Store.transition_workflow(issue_id, status,
             source: "user_ui",
             actor: AuthPlug.actor(conn),
             reason: "created from dashboard"
           ) do
        {:ok, _workflow} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp sync_issue_notes(conn, issue) do
    with {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
         {:ok, raw_notes} <- Client.list_issue_notes(config, issue.iid, %{per_page: config.sync_page_size}, auth_opts) do
      notes = Enum.map(raw_notes, &Store.upsert_note(issue.id, NoteMapper.from_gitlab(&1)))
      {:ok, notes}
    end
  end

  defp create_user_note(conn, issue, body, files) do
    with {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
         {:ok, final_body, uploaded} <- upload_note_files(config, auth_opts, issue.id, body, files),
         {:ok, raw_note} <- create_note_with_cleanup(config, auth_opts, issue.iid, final_body, uploaded) do
      Store.upsert_note(issue.id, NoteMapper.from_gitlab(raw_note))
      :ok
    end
  end

  defp upload_files(params) when is_map(params) do
    files =
      [Map.get(params, "files", []), Map.get(params, "files[]", [])]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    if Enum.all?(files, &match?(%Upload{}, &1)) do
      {:ok, files}
    else
      {:error, {:validation, "invalid_upload", "Attachments must be uploaded as files"}}
    end
  end

  defp validate_note_body(body) when is_binary(body), do: :ok
  defp validate_note_body(_body), do: {:error, {:validation, "invalid_body", "Note body must be text"}}

  defp validate_note_payload(body, files) do
    if String.trim(body) == "" and files == [] do
      {:error, {:validation, "missing_body", "Note body or attachment is required"}}
    else
      :ok
    end
  end

  defp upload_note_files(config, auth_opts, issue_id, body, files) do
    Enum.reduce_while(files, {:ok, body, []}, fn file, {:ok, acc_body, uploaded} ->
      upload = %{
        path: file.path,
        filename: file.filename || "attachment",
        content_type: file.content_type || "application/octet-stream"
      }

      case Client.upload_project_file(config, upload, auth_opts) do
        {:ok, raw_upload} ->
          markdown = raw_upload |> upload_markdown(issue_id) |> String.trim()
          next_body = append_upload_markdown(acc_body, markdown)
          {:cont, {:ok, next_body, [uploaded_file(raw_upload) | uploaded]}}

        {:error, reason} ->
          cleanup_uploaded_files(config, auth_opts, uploaded)
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, final_body, uploaded} -> {:ok, final_body, Enum.reverse(uploaded)}
      other -> other
    end
  end

  defp upload_markdown(%{"markdown" => markdown}, issue_id) when is_binary(markdown) do
    rewrite_upload_markdown(markdown, issue_id)
  end

  defp upload_markdown(raw_upload, issue_id) do
    alt = raw_upload["alt"] || raw_upload["filename"] || "attachment"
    url = raw_upload["url"] || ""
    rewrite_upload_markdown("[#{alt}](#{url})", issue_id)
  end

  defp rewrite_upload_markdown(markdown, issue_id) do
    Regex.replace(@upload_markdown_re, markdown, fn _match, image_marker, alt, secret, filename ->
      proxy_path = upload_proxy_path(issue_id, secret, filename)
      "#{image_marker}[#{alt}](#{proxy_path})"
    end)
  end

  defp upload_proxy_path(issue_id, secret, filename) do
    "/api/issues/#{issue_id}/uploads/#{URI.encode(secret, &URI.char_unreserved?/1)}/#{URI.encode(URI.decode(filename), &URI.char_unreserved?/1)}"
  end

  defp append_upload_markdown(body, ""), do: body
  defp append_upload_markdown(body, markdown) when body in [nil, ""], do: markdown
  defp append_upload_markdown(body, markdown), do: String.trim_trailing(body) <> "\n\n" <> markdown

  defp uploaded_file(raw_upload) do
    %{
      secret: raw_upload["secret"] || secret_from_upload_url(raw_upload["url"]) || secret_from_upload_url(raw_upload["full_path"]),
      filename: raw_upload["filename"] || filename_from_upload_url(raw_upload["url"]) || filename_from_upload_url(raw_upload["full_path"])
    }
  end

  defp secret_from_upload_url(url) when is_binary(url) do
    case Regex.run(~r/\/uploads\/([0-9a-fA-F]{32})\//, url) do
      [_match, secret] -> secret
      _ -> nil
    end
  end

  defp secret_from_upload_url(_url), do: nil

  defp filename_from_upload_url(url) when is_binary(url) do
    case Regex.run(~r/\/uploads\/[0-9a-fA-F]{32}\/([^\/?#)]+)/, url) do
      [_match, filename] -> URI.decode(filename)
      _ -> nil
    end
  end

  defp filename_from_upload_url(_url), do: nil

  defp create_note_with_cleanup(config, auth_opts, issue_iid, body, uploaded) do
    case Client.create_issue_note(config, issue_iid, body, auth_opts) do
      {:ok, raw_note} ->
        {:ok, raw_note}

      {:error, %GitLabError{type: type} = reason} when type in [:validation_error, :unauthorized, :forbidden, :not_found] ->
        cleanup_uploaded_files(config, auth_opts, uploaded)
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_uploaded_files(config, auth_opts, uploaded) do
    Enum.each(uploaded, fn
      %{secret: secret, filename: filename} when is_binary(secret) and is_binary(filename) ->
        Client.delete_project_upload(config, secret, filename, auth_opts)

      _unknown ->
        :ok
    end)
  end

  defp require_upload_reference(issue, secret, filename) do
    if upload_referenced?(issue, secret, filename) do
      :ok
    else
      {:error, :upload_not_referenced}
    end
  end

  defp upload_referenced?(issue, secret, filename) do
    bodies =
      [issue.description]
      |> Enum.concat(Store.list_notes(issue.id) |> Enum.map(& &1.body))
      |> Enum.reject(&is_nil/1)

    Enum.any?(bodies, &body_references_upload?(&1, issue.id, secret, filename))
  end

  defp body_references_upload?(body, issue_id, secret, filename) when is_binary(body) do
    decoded_filename = URI.decode(filename)

    body =~ "/uploads/#{secret}/#{filename}" or
      body =~ "/uploads/#{secret}/#{decoded_filename}" or
      body =~ upload_proxy_path(issue_id, secret, filename) or
      body =~ upload_proxy_path(issue_id, secret, decoded_filename)
  end

  defp body_references_upload?(_body, _issue_id, _secret, _filename), do: false

  defp sync_gitlab_lifecycle(conn, issue, status) do
    cond do
      IssueLifecycle.close_status?(status) ->
        close_user_issue(conn, issue, IssueLifecycle.close_reason(status))

      IssueLifecycle.reopen_transition?(issue.workflow_status, status) ->
        reopen_user_issue(conn, issue)

      true ->
        :ok
    end
  end

  defp close_user_issue(_conn, %{gitlab_state: "closed"}, _reason), do: :ok

  defp close_user_issue(conn, issue, reason) do
    with {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
         {:ok, raw_issue} <- Client.update_project_issue(config, issue.iid, %{"state_event" => "close"}, auth_opts) do
      raw_issue |> IssueMapper.from_gitlab() |> Store.upsert_issue()
      Store.record_event("gitlab_issue_closed", "user_ui", %{reason: reason}, issue_id: issue.id, actor: AuthPlug.actor(conn))
      :ok
    end
  end

  defp reopen_user_issue(conn, issue) do
    case IssueLifecycle.reopen_attrs(issue) do
      :noop ->
        :ok

      attrs ->
        with {:ok, config, auth_opts} <- user_gitlab_context(conn, issue),
             {:ok, raw_issue} <- Client.update_project_issue(config, issue.iid, attrs, auth_opts) do
          raw_issue |> IssueMapper.from_gitlab() |> Store.upsert_issue()
          :ok
        end
    end
  end

  defp user_gitlab_context(conn, issue) do
    with {:ok, access_token} <- AuthPlug.oauth_access_token(conn),
         {:ok, config} <- project_config_for_issue(issue) do
      {:ok, config, [auth: {:bearer, access_token}]}
    end
  end

  defp project_config_for_issue(issue) do
    with project_id when is_binary(project_id) <- Map.get(issue, :gitlab_project_setting_id),
         %{} = project <- Store.project_by_id(project_id) do
      GitLabConfig.from_project_setting(project)
    else
      _ -> {:error, :project_not_found}
    end
  end

  defp current_project_setting_id(conn) do
    case AuthPlug.current_user(conn) do
      %{project_setting_id: project_setting_id} -> project_setting_id
      _ -> nil
    end
  end

  defp safe_header_filename(filename) when is_binary(filename) do
    filename
    |> String.replace(~r/["\r\n]/, "_")
    |> Path.basename()
  end

  defp safe_header_filename(_filename), do: "attachment"

  defp base_content_type(nil), do: "application/octet-stream"

  defp base_content_type(content_type) when is_binary(content_type) do
    content_type |> String.split(";", parts: 2) |> hd() |> String.trim()
  end

  defp base_content_type(_content_type), do: "application/octet-stream"

  defp error(conn, status, code, message) do
    conn |> put_status(status) |> json(%{error: %{code: code, message: message}})
  end
end
