defmodule SymphonyElixir.GitLab.IssueLifecycle do
  @moduledoc """
  Shared GitLab issue close/reopen rules for Symphony workflow transitions.
  """

  @reopened_label "reopen"
  @legacy_reopened_labels ["symphony::reopened"]

  @spec reopened_label() :: String.t()
  def reopened_label, do: @reopened_label

  @spec close_status?(term()) :: boolean()
  def close_status?(status), do: normalize(status) in ["done", "canceled"]

  @spec close_reason(term()) :: String.t()
  def close_reason(status), do: "workflow #{normalize(status)}"

  @spec reopen_transition?(term(), term()) :: boolean()
  def reopen_transition?(from_status, to_status) do
    normalize(from_status) == "canceled" and normalize(to_status) in ["backlog", "todo"]
  end

  @spec external_reopen?(map() | nil, map()) :: boolean()
  def external_reopen?(%{} = previous, %{} = current) do
    normalize_gitlab_state(Map.get(previous, :gitlab_state)) == "closed" and
      normalize_gitlab_state(Map.get(current, :gitlab_state)) == "opened" and
      normalize(Map.get(previous, :workflow_status)) == "canceled"
  end

  def external_reopen?(_previous, _current), do: false

  @spec reopen_attrs(map()) :: :noop | map()
  def reopen_attrs(issue) when is_map(issue) do
    issue
    |> maybe_put_reopen_event(%{})
    |> maybe_put_reopened_label(Map.get(issue, :labels, []))
    |> maybe_remove_legacy_reopened_labels(Map.get(issue, :labels, []))
    |> case do
      attrs when map_size(attrs) == 0 -> :noop
      attrs -> attrs
    end
  end

  @spec has_reopened_label?([String.t()] | nil) :: boolean()
  def has_reopened_label?(labels) when is_list(labels) do
    Enum.any?(labels, &(normalize_label(&1) == normalize_label(@reopened_label)))
  end

  def has_reopened_label?(_labels), do: false

  defp maybe_put_reopen_event(issue, attrs) do
    if normalize_gitlab_state(Map.get(issue, :gitlab_state)) == "closed" do
      Map.put(attrs, "state_event", "reopen")
    else
      attrs
    end
  end

  defp maybe_put_reopened_label(attrs, labels) do
    if has_reopened_label?(labels) do
      attrs
    else
      Map.put(attrs, "add_labels", @reopened_label)
    end
  end

  defp maybe_remove_legacy_reopened_labels(attrs, labels) do
    legacy_names = MapSet.new(@legacy_reopened_labels, fn label -> normalize_label(label) end)

    legacy_labels =
      labels
      |> List.wrap()
      |> Enum.filter(fn label -> MapSet.member?(legacy_names, normalize_label(label)) end)

    if legacy_labels == [] do
      attrs
    else
      Map.put(attrs, "remove_labels", Enum.join(legacy_labels, ","))
    end
  end

  defp normalize(status) when is_atom(status), do: status |> Atom.to_string() |> normalize()
  defp normalize(status) when is_binary(status), do: status |> String.trim() |> String.downcase() |> String.replace("-", "_")
  defp normalize(_status), do: ""

  defp normalize_gitlab_state(state) when is_binary(state), do: state |> String.trim() |> String.downcase()
  defp normalize_gitlab_state(_state), do: ""

  defp normalize_label(label) when is_binary(label), do: label |> String.trim() |> String.downcase()
  defp normalize_label(label), do: label |> to_string() |> normalize_label()
end
