defmodule Mix.Tasks.Symphony.Gitlab.Setup do
  @moduledoc """
  Creates or updates `.env.local` with GitLab project configuration.
  """

  use Mix.Task

  alias Symphony.GitLab.Config
  alias SymphonyElixir.Dotenv

  @shortdoc "Configure local GitLab access"

  @impl true
  def run(_args) do
    Mix.shell().info("Configure Symphony GitLab access")
    project_url = prompt("GitLab project API URL: ")
    token = hidden_prompt("GitLab token: ")

    Dotenv.load()

    entries =
      %{
        "GITLAB_PROJECT_API_URL" => String.trim(project_url),
        "GITLAB_TOKEN" => String.trim(token),
        "SYMPHONY_BIND_HOST" => System.get_env("SYMPHONY_BIND_HOST") || "127.0.0.1"
      }

    write_env_local(entries)

    case Config.parse_project_api_url(entries["GITLAB_PROJECT_API_URL"]) do
      {:ok, config} ->
        Mix.shell().info("Wrote .env.local")
        Mix.shell().info("Detected API root: #{config.gitlab_api_root}")
        Mix.shell().info("Detected project: #{config.gitlab_project_ref}")
        Mix.shell().info("Token: [REDACTED]")
        Mix.shell().info("Run: mix symphony.gitlab.test")

      {:error, reason} ->
        Mix.raise("Invalid GitLab project API URL: #{reason.message}")
    end
  end

  defp prompt(label) do
    label
    |> IO.gets()
    |> case do
      nil -> ""
      value -> value
    end
  end

  defp hidden_prompt(label) do
    label
    |> String.to_charlist()
    |> :io.get_password()
    |> case do
      chars when is_list(chars) -> List.to_string(chars)
      _ -> ""
    end
  rescue
    _ ->
      prompt(label)
  end

  defp write_env_local(entries) do
    path = Path.expand(".env.local")
    existing = read_env_file(path)
    merged = Map.merge(existing, entries)

    body =
      merged
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map(fn {key, value} -> "#{key}=#{escape(value)}\n" end)
      |> IO.iodata_to_binary()

    File.write!(path, body)
  end

  defp read_env_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        contents
        |> String.split(["\n", "\r\n"], trim: true)
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, "=", parts: 2) do
            [key, value] -> Map.put(acc, key, value)
            _ -> acc
          end
        end)

      _ ->
        %{}
    end
  end

  defp escape(value) do
    value
    |> to_string()
    |> String.replace("\n", "")
  end
end
