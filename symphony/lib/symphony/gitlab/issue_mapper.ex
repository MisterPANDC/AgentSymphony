defmodule Symphony.GitLab.IssueMapper do
  @moduledoc """
  Converts raw GitLab issue payloads into Symphony's read model attributes.
  """

  @spec from_gitlab(map()) :: map()
  def from_gitlab(%{} = raw) do
    description = raw["description"]

    %{
      gitlab_issue_id: raw["id"],
      gitlab_project_id: raw["project_id"],
      iid: raw["iid"],
      identifier: "GL-#{raw["iid"]}",
      web_url: raw["web_url"],
      title: raw["title"] || "(untitled)",
      description: description,
      description_preview: preview(description),
      gitlab_state: raw["state"] || "opened",
      labels: labels(raw["labels"]),
      assignees: assignees(raw["assignees"]),
      author: slim_user(raw["author"]),
      milestone: raw["milestone"],
      due_date: parse_date(raw["due_date"]),
      confidential: raw["confidential"] == true,
      gitlab_created_at: parse_datetime(raw["created_at"]),
      gitlab_updated_at: parse_datetime(raw["updated_at"]),
      closed_at: parse_datetime(raw["closed_at"]),
      last_synced_at: DateTime.utc_now(),
      raw_gitlab: raw
    }
  end

  defp labels(labels) when is_list(labels), do: Enum.map(labels, &to_string/1)
  defp labels(_labels), do: []

  defp assignees(users) when is_list(users), do: Enum.map(users, &slim_user/1) |> Enum.reject(&is_nil/1)
  defp assignees(_users), do: []

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

  defp preview(nil), do: nil

  defp preview(text) when is_binary(text) do
    text
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> String.slice(0, 220)
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_date(nil), do: nil

  defp parse_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> nil
    end
  end
end
