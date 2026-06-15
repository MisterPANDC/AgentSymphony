defmodule Symphony.GitLab.MergeRequestMapper do
  @moduledoc """
  Converts raw GitLab merge request payloads into Symphony's local read model.
  """

  @spec from_gitlab(map()) :: map()
  def from_gitlab(%{} = raw) do
    %{
      merge_request_id: raw["id"],
      iid: raw["iid"],
      title: raw["title"] || "(untitled)",
      description: raw["description"],
      state: raw["state"] || "opened",
      draft: raw["draft"] || raw["work_in_progress"] || false,
      work_in_progress: raw["work_in_progress"] || false,
      web_url: raw["web_url"],
      source_branch: raw["source_branch"],
      target_branch: raw["target_branch"],
      merge_status: raw["merge_status"],
      detailed_merge_status: raw["detailed_merge_status"],
      labels: labels(raw["labels"]),
      author: slim_user(raw["author"]),
      assignees: users(raw["assignees"]),
      reviewers: users(raw["reviewers"]),
      milestone: raw["milestone"],
      user_notes_count: raw["user_notes_count"],
      upvotes: raw["upvotes"],
      downvotes: raw["downvotes"],
      changes_count: changes_count(raw["changes_count"]),
      references: raw["references"] || %{},
      head_pipeline: raw["head_pipeline"] || raw["pipeline"],
      gitlab_created_at: parse_datetime(raw["created_at"]),
      gitlab_updated_at: parse_datetime(raw["updated_at"]),
      merged_at: parse_datetime(raw["merged_at"]),
      closed_at: parse_datetime(raw["closed_at"]),
      last_synced_at: DateTime.utc_now(),
      raw_gitlab: raw
    }
  end

  defp labels(labels) when is_list(labels), do: Enum.map(labels, &to_string/1)
  defp labels(_labels), do: []

  defp users(users) when is_list(users), do: users |> Enum.map(&slim_user/1) |> Enum.reject(&is_nil/1)
  defp users(_users), do: []

  defp slim_user(%{} = user) do
    %{
      id: user["id"],
      username: user["username"],
      name: user["name"],
      avatar_url: user["avatar_url"] || user["avatarUrl"],
      web_url: user["web_url"]
    }
  end

  defp slim_user(_user), do: nil

  defp changes_count(nil), do: nil
  defp changes_count(value), do: to_string(value)

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end
end
