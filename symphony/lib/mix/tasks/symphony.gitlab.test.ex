defmodule Mix.Tasks.Symphony.Gitlab.Test do
  @moduledoc """
  Validates configured GitLab project and issue API reachability.
  """

  use Mix.Task

  alias Symphony.GitLab.{Client, Config}
  alias SymphonyElixir.Dotenv

  @shortdoc "Test GitLab project access"

  @impl true
  def run(_args) do
    Dotenv.load()
    {:ok, _apps} = Application.ensure_all_started(:req)

    case run_validation() do
      :ok -> :ok
      {:error, reason} -> Mix.raise(format_error(reason))
    end
  end

  defp run_validation do
    with {:ok, config} <- Config.load(load_env_file: false),
         :ok <- Client.validate_api_root(config),
         {:ok, project} <- Client.get_project(config),
         {:ok, issues} <- Client.list_project_issues(config, per_page: 1, state: "all") do
      Mix.shell().info("GitLab API root: #{config.gitlab_api_root}")
      Mix.shell().info("Project ref: #{config.gitlab_project_ref}")
      Mix.shell().info("Project name: #{project["name"]}")
      Mix.shell().info("Project web URL: #{project["web_url"]}")
      Mix.shell().info("Default branch: #{project["default_branch"] || "n/a"}")
      Mix.shell().info("Token permission mode: read_only_or_read_write")
      Mix.shell().info("Issue API reachable: #{is_list(issues)}")
      Mix.shell().info("Token: [REDACTED]")
      :ok
    end
  end

  defp format_error(%{type: type, status: status, message: message}) do
    "GitLab validation failed type=#{type} status=#{inspect(status)} message=#{message}"
  end

  defp format_error(reason), do: "GitLab validation failed: #{inspect(reason)}"
end
