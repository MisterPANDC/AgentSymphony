defmodule SymphonyElixir.LocalRepo do
  @moduledoc """
  Local repository path validation and nearby candidate discovery.
  """

  @type validation_result :: %{
          path: String.t(),
          git_root: String.t(),
          remote_url: String.t() | nil
        }

  @type candidate :: %{
          path: String.t(),
          git_root: String.t(),
          remote_url: String.t() | nil,
          reason: String.t(),
          score: non_neg_integer()
        }

  @type search_scope :: :nearby | :local

  @local_search_depth 4
  @local_search_limit 2_500
  @local_search_match_limit 16

  @spec validate_path(String.t()) :: {:ok, validation_result()} | {:error, term()}
  def validate_path(path) when is_binary(path) do
    trimmed = String.trim(path)
    expanded = Path.expand(trimmed)

    cond do
      trimmed == "" ->
        {:error, :empty_local_repo_path}

      String.contains?(trimmed, <<0>>) ->
        {:error, :invalid_local_repo_path}

      not File.dir?(expanded) ->
        {:error, :local_repo_path_not_found}

      true ->
        with {:ok, git_root} <- git_root(expanded) do
          {:ok, %{path: git_root, git_root: git_root, remote_url: origin_url(git_root)}}
        end
    end
  end

  def validate_path(_path), do: {:error, :invalid_local_repo_path}

  @spec validate_project_path(String.t(), map()) :: {:ok, validation_result()} | {:error, term()}
  def validate_project_path(path, project) do
    with {:ok, repo} <- validate_path(path),
         :ok <- validate_remote(repo.remote_url, project) do
      {:ok, repo}
    end
  end

  @spec candidates(map() | nil, keyword()) :: [candidate()]
  def candidates(project, opts \\ []) do
    scope = opts |> Keyword.get(:scope, :nearby) |> normalize_scope()
    names = project_names(project)

    names
    |> candidate_paths(scope)
    |> Enum.uniq_by(fn {path, _source} -> path end)
    |> Enum.flat_map(&candidate_for_path(&1, project))
    |> Enum.sort_by(&{-&1.score, &1.path})
    |> Enum.take(8)
  end

  defp candidate_for_path({path, source}, project) do
    case validate_path(path) do
      {:ok, repo} ->
        if remote_matches_project?(repo.remote_url, project) do
          [
            %{
              path: repo.path,
              git_root: repo.git_root,
              remote_url: repo.remote_url,
              reason: candidate_reason(source),
              score: candidate_score(source)
            }
          ]
        else
          []
        end

      {:error, _reason} ->
        []
    end
  end

  defp normalize_scope(scope) when scope in [:nearby, "nearby"], do: :nearby
  defp normalize_scope(scope) when scope in [:local, "local"], do: :local
  defp normalize_scope(_scope), do: :nearby

  defp validate_remote(nil, _project), do: {:error, :local_repo_remote_missing}

  defp validate_remote(remote_url, project) do
    if remote_matches_project?(remote_url, project) do
      :ok
    else
      {:error, :local_repo_project_mismatch}
    end
  end

  defp candidate_paths(names, :nearby), do: nearby_candidate_paths(names)

  defp candidate_paths(names, :local) do
    nearby_candidate_paths(names) ++ local_candidate_paths(names)
  end

  defp nearby_candidate_paths(names) do
    names
    |> Enum.flat_map(fn name ->
      nearby_roots()
      |> Enum.flat_map(fn root ->
        [
          Path.join(root, name),
          Path.join(root, String.replace(name, "_", "-")),
          Path.join(root, String.replace(name, "-", "_"))
        ]
      end)
    end)
    |> Enum.map(&{&1, :nearby})
  end

  defp local_candidate_paths(names) do
    candidates = names |> Enum.map(&Path.basename/1) |> Enum.flat_map(&name_variants/1) |> Enum.uniq()

    local_search_roots()
    |> Enum.reduce_while([], fn root, acc ->
      remaining = @local_search_match_limit - length(acc)
      matches = matching_directories(root, candidates, remaining)
      acc = acc ++ matches

      if length(acc) >= @local_search_match_limit do
        {:halt, acc}
      else
        {:cont, acc}
      end
    end)
    |> Enum.map(&{&1, :local})
  end

  defp name_variants(name) do
    [
      name,
      String.replace(name, "_", "-"),
      String.replace(name, "-", "_")
    ]
    |> Enum.reject(&(&1 == ""))
  end

  defp nearby_roots do
    cwd = File.cwd!()
    app_root = Application.app_dir(:symphony_elixir) |> Path.expand()

    [
      cwd,
      Path.dirname(cwd),
      Path.dirname(Path.dirname(cwd)),
      app_root,
      Path.dirname(app_root),
      Path.dirname(Path.dirname(app_root))
    ]
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
  end

  defp local_search_roots do
    home = System.user_home()
    cwd_roots = nearby_roots()

    home_roots =
      if is_binary(home) do
        [
          Path.join(home, "Projects"),
          Path.join(home, "Developer"),
          Path.join(home, "Code"),
          Path.join(home, "src"),
          Path.join(home, "work"),
          Path.join(home, ".codex/worktrees"),
          Path.join(home, "Documents"),
          Path.join(home, "Desktop")
        ]
      else
        []
      end

    (cwd_roots ++ home_roots)
    |> Enum.map(&Path.expand/1)
    |> Enum.uniq()
    |> Enum.filter(&File.dir?/1)
  end

  defp matching_directories(_root, _names, match_limit) when match_limit <= 0, do: []

  defp matching_directories(root, names, match_limit) do
    names = MapSet.new(names)

    root
    |> do_matching_directories(names, @local_search_depth, [], 0, match_limit)
    |> elem(0)
    |> Enum.reverse()
  end

  defp do_matching_directories(_root, _names, depth, acc, count, match_limit)
       when depth < 0 or count >= @local_search_limit or length(acc) >= match_limit,
       do: {acc, count}

  defp do_matching_directories(root, names, depth, acc, count, match_limit) do
    if skip_directory?(root) do
      {acc, count}
    else
      acc = if MapSet.member?(names, Path.basename(root)), do: [root | acc], else: acc

      if depth == 0 or length(acc) >= match_limit do
        {acc, count + 1}
      else
        root
        |> child_directories()
        |> Enum.reduce_while({acc, count + 1}, fn child, {acc, count} ->
          if count >= @local_search_limit or length(acc) >= match_limit do
            {:halt, {acc, count}}
          else
            {:cont, do_matching_directories(child, names, depth - 1, acc, count, match_limit)}
          end
        end)
      end
    end
  end

  defp child_directories(root) do
    root
    |> File.ls()
    |> case do
      {:ok, entries} ->
        entries
        |> Enum.map(&Path.join(root, &1))
        |> Enum.filter(&File.dir?/1)

      {:error, _reason} ->
        []
    end
  end

  defp skip_directory?(path) do
    Path.basename(path) in [
      ".git",
      ".cache",
      ".Trash",
      "Library",
      "Applications",
      "node_modules",
      "deps",
      "_build",
      "priv"
    ]
  end

  defp project_names(project) when is_map(project) do
    [
      project[:path_with_namespace],
      project["path_with_namespace"],
      project[:project_ref],
      project["project_ref"],
      project[:name],
      project["name"]
    ]
    |> Enum.filter(&is_binary/1)
    |> Enum.flat_map(fn value ->
      basename = value |> String.trim() |> String.split("/") |> List.last()
      [value, basename]
    end)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.uniq()
  end

  defp project_names(_project), do: []

  defp git_root(path) do
    case System.cmd("git", ["-C", path, "rev-parse", "--show-toplevel"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output |> String.trim() |> Path.expand()}
      {_output, _status} -> {:error, :not_a_git_repository}
    end
  rescue
    _error in ErlangError -> {:error, :git_unavailable}
  end

  defp origin_url(path) do
    case System.cmd("git", ["-C", path, "config", "--get", "remote.origin.url"], stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {_output, _status} -> nil
    end
  rescue
    _error in ErlangError -> nil
  end

  defp candidate_reason(:nearby), do: "Found nearby; origin remote matches this GitLab project."
  defp candidate_reason(:local), do: "Found by wider local search; origin remote matches this GitLab project."

  defp candidate_score(:nearby), do: 100
  defp candidate_score(:local), do: 90

  defp remote_matches_project?(remote_url, project) when is_binary(remote_url) and is_map(project) do
    path =
      project[:path_with_namespace] || project["path_with_namespace"] ||
        project[:project_ref] || project["project_ref"]

    is_binary(path) and remote_key(remote_url) == remote_key(path) and remote_host_matches_project?(remote_url, project)
  end

  defp remote_matches_project?(_remote_url, _project), do: false

  defp remote_host_matches_project?(remote_url, project) do
    remote_host = remote_host(remote_url)
    project_host = project_host(project)

    is_nil(remote_host) or is_nil(project_host) or remote_host == project_host
  end

  defp project_host(project) do
    [
      project[:web_url],
      project["web_url"],
      project[:api_root],
      project["api_root"]
    ]
    |> Enum.find_value(&url_host/1)
  end

  defp remote_host(value) do
    value = String.trim(value)

    cond do
      String.starts_with?(value, "git@") ->
        value
        |> String.replace_prefix("git@", "")
        |> String.split(":", parts: 2)
        |> List.first()
        |> normalize_host()

      true ->
        url_host(value)
    end
  end

  defp url_host(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{host: host} when is_binary(host) -> normalize_host(host)
      _ -> nil
    end
  end

  defp url_host(_value), do: nil

  defp normalize_host(host) when is_binary(host) do
    host
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_host(_host), do: nil

  defp remote_key(value) do
    value = String.trim(value)

    value =
      case URI.parse(value) do
        %URI{host: host, path: path} when is_binary(host) and is_binary(path) ->
          String.trim_leading(path, "/")

        _ ->
          value
      end

    value
    |> String.replace(~r/\.git$/, "")
    |> String.replace(~r/^git@[^:]+:/, "")
    |> String.downcase()
  end
end
