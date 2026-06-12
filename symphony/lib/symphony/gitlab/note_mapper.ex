defmodule Symphony.GitLab.NoteMapper do
  @moduledoc """
  Converts raw GitLab issue note payloads into Symphony note read model attrs.
  """

  @spec from_gitlab(map()) :: map()
  def from_gitlab(%{} = raw) do
    %{
      note_id: raw["id"],
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
