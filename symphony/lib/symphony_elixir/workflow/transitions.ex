defmodule SymphonyElixir.Workflow.Transitions do
  @moduledoc """
  Central workflow status transition rules for the GitLab-backed issue model.
  """

  @statuses ~w(triage todo in_progress review merging rework done canceled)
  @dispatch_candidate_statuses ~w(todo in_progress merging rework)

  @type status :: String.t()

  @spec statuses() :: [status()]
  def statuses, do: @statuses

  @spec dispatch_candidate_statuses() :: [status()]
  def dispatch_candidate_statuses, do: @dispatch_candidate_statuses

  @spec dispatch_candidate?(term()) :: boolean()
  def dispatch_candidate?(status) when is_binary(status), do: normalize(status) in @dispatch_candidate_statuses
  def dispatch_candidate?(_status), do: false

  @spec allowed?(term(), term(), keyword()) :: boolean()
  def allowed?(from, to, opts \\ []) do
    from = normalize(from)
    to = normalize(to)
    source = normalize_source(Keyword.get(opts, :source, "system"))

    cond do
      from == to ->
        true

      from in ["done", "canceled"] ->
        false

      source == "user_ui" ->
        user_transition_allowed?(from, to)

      true ->
        system_transition_allowed?(from, to)
    end
  end

  @spec user_targets(term()) :: [status()]
  def user_targets(from) do
    from = normalize(from)

    @statuses
    |> Enum.reject(&(&1 == from))
    |> Enum.filter(&allowed?(from, &1, source: "user_ui"))
  end

  @spec normalize(term()) :: status()
  def normalize(status) when is_binary(status), do: status |> String.trim() |> String.downcase()
  def normalize(_status), do: ""

  defp normalize_source(source) when is_atom(source), do: source |> Atom.to_string() |> normalize()
  defp normalize_source(source), do: normalize(source)

  defp user_transition_allowed?("triage", status), do: status in ["todo", "canceled"]
  defp user_transition_allowed?("todo", status), do: status in ["triage", "canceled"]
  defp user_transition_allowed?("in_progress", status), do: status in ["triage", "canceled"]
  defp user_transition_allowed?("review", status), do: status in ["triage", "merging", "rework", "canceled"]
  defp user_transition_allowed?("rework", status), do: status in ["triage", "canceled"]
  defp user_transition_allowed?(_from, "canceled"), do: true
  defp user_transition_allowed?(_from, _to), do: false

  defp system_transition_allowed?(_from, "canceled"), do: true
  defp system_transition_allowed?("triage", "todo"), do: true
  defp system_transition_allowed?("todo", status), do: status in ["in_progress", "triage"]
  defp system_transition_allowed?("in_progress", status), do: status in ["review", "todo", "triage"]
  defp system_transition_allowed?("review", status), do: status in ["todo", "merging", "rework", "triage"]
  defp system_transition_allowed?("merging", status), do: status in ["done", "review"]
  defp system_transition_allowed?("rework", status), do: status in ["in_progress", "review", "triage"]
  defp system_transition_allowed?(_from, _to), do: false
end
