defmodule SymphonyElixir.Tracker.Issue do
  @moduledoc """
  Normalized GitLab issue representation used by orchestration and prompts.
  """

  defstruct [
    :id,
    :identifier,
    :iid,
    :title,
    :description,
    :priority,
    :state,
    :workflow_status,
    :gitlab_state,
    :branch_name,
    :url,
    :web_url,
    :assignee_id,
    notes_summary: nil,
    blockers: [],
    blocked_by: [],
    labels: [],
    assignees: [],
    assigned_to_worker: true,
    created_at: nil,
    updated_at: nil
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          identifier: String.t() | nil,
          iid: integer() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          priority: integer() | nil,
          state: String.t() | nil,
          workflow_status: String.t() | nil,
          gitlab_state: String.t() | nil,
          branch_name: String.t() | nil,
          url: String.t() | nil,
          web_url: String.t() | nil,
          labels: [String.t()],
          assignees: [map()],
          assigned_to_worker: boolean(),
          created_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @spec label_names(t()) :: [String.t()]
  def label_names(%__MODULE__{labels: labels}), do: labels

  @spec routable?(t(), [String.t()]) :: boolean()
  def routable?(%__MODULE__{assigned_to_worker: true, labels: labels}, required_labels)
      when is_list(labels) and is_list(required_labels) do
    issue_labels = MapSet.new(labels, &normalize_label/1)
    Enum.all?(required_labels, &MapSet.member?(issue_labels, normalize_label(&1)))
  end

  def routable?(%__MODULE__{}, _required_labels), do: false

  defp normalize_label(label) when is_binary(label) do
    label |> String.trim() |> String.downcase()
  end
end
