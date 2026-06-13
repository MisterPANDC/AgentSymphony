defmodule SymphonyElixir.Tracker.GitLab do
  @moduledoc """
  GitLab-backed tracker adapter reading from Symphony's local read model.
  """

  @behaviour SymphonyElixir.Tracker

  alias Symphony.{GitLab.Client, GitLab.Config, GitLab.IssueMapper, GitLab.NoteMapper}
  alias SymphonyElixir.Store

  @followup_keys ~w(title description acceptance_criteria labels assignee_ids milestone_id due_date confidential related_to_current_issue blocked_by_current_issue)a

  @impl true
  def fetch_candidate_issues do
    tracker = SymphonyElixir.Config.settings!().tracker
    {:ok, Store.list_candidate_tracker_issues(tracker.required_labels, tracker.active_states)}
  end

  @impl true
  def fetch_issues_by_states(statuses) do
    {:ok, Store.tracker_issues_by_workflow_statuses(statuses)}
  end

  @impl true
  def fetch_issue_states_by_ids(issue_ids) do
    {:ok, Store.tracker_issues_by_ids(issue_ids)}
  end

  @impl true
  def create_comment(issue_id, body) when is_binary(issue_id) and is_binary(body) do
    with %{} = issue <- Store.get_issue(issue_id),
         {:ok, config} <- project_gitlab_config(issue),
         {:ok, raw_note} <- Client.create_issue_note(config, issue.iid, body) do
      Store.upsert_note(issue_id, NoteMapper.from_gitlab(raw_note))
      :ok
    else
      nil -> {:error, :issue_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def update_issue_state(issue_id, status) when is_binary(issue_id) and is_binary(status) do
    case Store.transition_workflow(issue_id, status, source: "agent", actor: "agent") do
      {:ok, _workflow} ->
        maybe_close_issue(issue_id, status)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def create_followup_issue(current_issue_id, attrs) when is_binary(current_issue_id) and is_map(attrs) do
    with %{} = current_issue <- Store.get_issue(current_issue_id),
         {:ok, config} <- project_gitlab_config(current_issue),
         {:ok, request} <- followup_issue_request(current_issue, attrs),
         {:ok, raw_issue} <- Client.create_project_issue(config, request.gitlab_attrs) do
      persist_followup_issue(config, current_issue, raw_issue, request)
    else
      nil -> {:error, :issue_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def close_issue(issue_id) when is_binary(issue_id), do: do_close_issue(issue_id)

  defp maybe_close_issue(issue_id, status) do
    if normalize_status(status) == "done" do
      do_close_issue(issue_id)
    else
      :ok
    end
  end

  defp do_close_issue(issue_id) do
    with %{} = issue <- Store.get_issue(issue_id),
         {:ok, config} <- project_gitlab_config(issue),
         true <- issue.gitlab_state != "closed" || :already_closed,
         {:ok, raw_issue} <- Client.update_project_issue(config, issue.iid, %{"state_event" => "close"}) do
      raw_issue |> IssueMapper.from_gitlab() |> Store.upsert_issue()
      Store.record_event("gitlab_issue_closed", "system", %{reason: "workflow done"}, issue_id: issue_id, actor: "orchestrator")
      :ok
    else
      :already_closed ->
        :ok

      nil ->
        record_close_failure(issue_id, :issue_not_found)
        {:error, :issue_not_found}

      {:error, reason} ->
        record_close_failure(issue_id, reason)
        {:error, reason}
    end
  end

  defp record_close_failure(issue_id, reason) do
    Store.record_event("gitlab_issue_close_failed", "system", %{reason: inspect(reason)}, issue_id: issue_id, actor: "orchestrator")
  rescue
    _ -> :ok
  end

  defp followup_issue_request(current_issue, attrs) do
    attrs = atomize_keys(attrs)

    with {:ok, title} <- required_string(attrs, :title),
         {:ok, description} <- required_string(attrs, :description),
         {:ok, acceptance_criteria} <- acceptance_criteria(attrs[:acceptance_criteria]) do
      blocked = truthy?(Map.get(attrs, :blocked_by_current_issue, false))
      related = truthy?(Map.get(attrs, :related_to_current_issue, true)) or blocked

      gitlab_attrs =
        %{
          "title" => title,
          "description" => followup_description(current_issue, description, acceptance_criteria, related)
        }
        |> maybe_put("labels", labels(attrs[:labels]))
        |> maybe_put("assignee_ids", int_list(attrs[:assignee_ids]))
        |> maybe_put("milestone_id", optional_int(attrs[:milestone_id]))
        |> maybe_put("due_date", optional_string(attrs[:due_date]))
        |> maybe_put("confidential", optional_boolean(attrs[:confidential]))

      {:ok,
       %{
         gitlab_attrs: gitlab_attrs,
         related_to_current_issue: related,
         blocked_by_current_issue: blocked,
         acceptance_criteria: acceptance_criteria
       }}
    end
  end

  defp persist_followup_issue(config, current_issue, raw_issue, request) do
    try do
      created_issue =
        raw_issue
        |> IssueMapper.from_gitlab()
        |> Store.upsert_issue()

      related_relation =
        if request.related_to_current_issue do
          {:ok, relation} =
            Store.add_issue_relation(current_issue.id, created_issue.id, "relates_to",
              source: "agent",
              actor: "agent",
              reason: "agent-created follow-up",
              metadata: %{"kind" => "followup"}
            )

          relation
        end

      blocker =
        if request.blocked_by_current_issue do
          {:ok, edge} =
            Store.add_blocker(created_issue.id, current_issue.id,
              source: "agent",
              actor: "agent",
              reason: "follow-up depends on current issue"
            )

          edge
        end

      note_created = maybe_post_followup_note(config, current_issue, created_issue, request)

      event =
        Store.record_event(
          "followup_issue_created",
          "agent",
          %{
            current_issue_id: current_issue.id,
            created_issue_id: created_issue.id,
            created_issue_iid: created_issue.iid,
            related_to_current_issue: request.related_to_current_issue,
            blocked_by_current_issue: request.blocked_by_current_issue
          },
          issue_id: current_issue.id,
          actor: "agent"
        )

      {:ok,
       %{
         issue: created_issue,
         relationship_flags: %{
           related_to_current_issue: request.related_to_current_issue,
           blocked_by_current_issue: request.blocked_by_current_issue
         },
         related_relation: related_relation,
         dependency: blocker,
         note_created: note_created,
         event: event
       }}
    rescue
      error ->
        record_followup_persistence_failure(current_issue.id, raw_issue, error)
        {:error, {:followup_persistence_failed, Exception.message(error)}}
    end
  end

  defp maybe_post_followup_note(_config, _current_issue, _created_issue, %{related_to_current_issue: false}), do: false

  defp maybe_post_followup_note(config, current_issue, created_issue, request) do
    body = followup_note_body(created_issue, request)

    case Client.create_issue_note(config, current_issue.iid, body) do
      {:ok, raw_note} ->
        Store.upsert_note(current_issue.id, NoteMapper.from_gitlab(raw_note))
        true

      {:error, reason} ->
        raise "failed to create follow-up note: #{inspect(reason)}"
    end
  end

  defp followup_description(current_issue, description, acceptance_criteria, related?) do
    [
      description,
      "## Acceptance Criteria\n#{acceptance_criteria}",
      related_source_section(current_issue, related?)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp related_source_section(_current_issue, false), do: nil

  defp related_source_section(current_issue, true) do
    "## Source\nCreated as a follow-up from #{current_issue.identifier}: #{current_issue.web_url}"
  end

  defp followup_note_body(created_issue, request) do
    dependency =
      if request.blocked_by_current_issue do
        "\n\nThis follow-up is blocked by the current issue."
      else
        ""
      end

    "Created follow-up issue [#{created_issue.identifier}](#{created_issue.web_url}): #{created_issue.title}.#{dependency}"
  end

  defp record_followup_persistence_failure(current_issue_id, raw_issue, error) do
    Store.create_runtime_block(
      current_issue_id,
      "external_failure",
      "Created GitLab follow-up issue but local persistence failed.",
      %{
        raw_gitlab_issue: raw_issue,
        error: Exception.message(error)
      }
    )
  rescue
    _ -> :ok
  end

  defp project_gitlab_config(issue) do
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

  defp required_string(attrs, key) do
    case attrs[key] do
      value when is_binary(value) ->
        value = String.trim(value)
        if value == "", do: {:error, {:missing_required_followup_field, key}}, else: {:ok, value}

      _ ->
        {:error, {:missing_required_followup_field, key}}
    end
  end

  defp acceptance_criteria(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: {:error, {:missing_required_followup_field, :acceptance_criteria}}, else: {:ok, value}
  end

  defp acceptance_criteria(values) when is_list(values) do
    values =
      values
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case values do
      [] -> {:error, {:missing_required_followup_field, :acceptance_criteria}}
      _ -> {:ok, Enum.map_join(values, "\n", &"- #{&1}")}
    end
  end

  defp acceptance_criteria(_value), do: {:error, {:missing_required_followup_field, :acceptance_criteria}}

  defp labels(labels) when is_list(labels) do
    labels =
      labels
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    if labels == [], do: nil, else: Enum.join(labels, ",")
  end

  defp labels(_labels), do: nil

  defp int_list(values) when is_list(values) do
    values =
      values
      |> Enum.map(&optional_int/1)
      |> Enum.reject(&is_nil/1)

    if values == [], do: nil, else: values
  end

  defp int_list(_values), do: nil

  defp optional_int(value) when is_integer(value), do: value

  defp optional_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp optional_int(_value), do: nil

  defp optional_string(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp optional_string(_value), do: nil

  defp optional_boolean(value) when is_boolean(value), do: value
  defp optional_boolean(_value), do: nil

  defp truthy?(value) when is_boolean(value), do: value
  defp truthy?(value) when is_binary(value), do: (value |> String.trim() |> String.downcase()) in ["true", "1", "yes"]
  defp truthy?(_value), do: false

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp atomize_keys(map) when is_map(map) do
    Map.new(@followup_keys, fn key ->
      {key, Map.get(map, key, Map.get(map, Atom.to_string(key)))}
    end)
  end

  defp normalize_status(status) when is_binary(status), do: status |> String.trim() |> String.downcase()
  defp normalize_status(_status), do: ""
end
