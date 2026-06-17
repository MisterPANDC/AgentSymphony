defmodule Symphony.GitLab.NoteMapper do
  @moduledoc """
  Converts raw GitLab issue note payloads into Symphony note read model attrs.
  """

  @spec from_gitlab(map()) :: map()
  def from_gitlab(%{} = raw) do
    %{
      id: "gitlab-note-#{raw["id"]}",
      note_id: raw["id"],
      discussion_id: raw["discussion_id"],
      discussion_reply: raw["discussion_reply"] == true,
      discussion_individual_note: raw["discussion_individual_note"] == true,
      discussion_position: raw["discussion_position"],
      body: raw["body"] || "",
      author: slim_user(raw["author"]),
      system: raw["system"] == true,
      internal: raw["internal"] == true,
      resolvable: raw["resolvable"] == true,
      gitlab_created_at: parse_datetime(raw["created_at"]),
      gitlab_updated_at: parse_datetime(raw["updated_at"]),
      raw_gitlab: raw
    }
  end

  @spec from_gitlab_discussion(map()) :: [map()]
  def from_gitlab_discussion(%{} = discussion) do
    discussion_id = discussion["id"]
    individual_note? = discussion["individual_note"] == true

    discussion
    |> Map.get("notes", [])
    |> Enum.with_index()
    |> Enum.map(fn {raw, index} ->
      raw
      |> Map.put_new("discussion_id", discussion_id)
      |> Map.put("discussion_reply", index > 0)
      |> Map.put("discussion_individual_note", individual_note?)
      |> Map.put("discussion_position", index)
      |> from_gitlab()
    end)
  end

  def from_gitlab_discussion(_discussion), do: []

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

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end
end
