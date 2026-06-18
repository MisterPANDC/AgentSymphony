defmodule SymphonyElixir.PrivAssets do
  @moduledoc false

  @app :symphony_elixir

  @spec agent_mcp_install_script() :: {:ok, String.t()} | {:error, {:mcp_install_script_missing, String.t()}}
  def agent_mcp_install_script do
    find_priv_file(["agent_mcp", "install.sh"], :mcp_install_script_missing)
  end

  defp find_priv_file(relative_segments, missing_tag) do
    priv_dirs = priv_dir_candidates()

    case Enum.find_value(priv_dirs, &existing_priv_file(&1, relative_segments)) do
      nil ->
        fallback =
          priv_dirs
          |> List.first()
          |> Kernel.||("priv")
          |> Path.join(relative_segments)

        {:error, {missing_tag, fallback}}

      path ->
        {:ok, path}
    end
  end

  defp existing_priv_file(priv_dir, relative_segments) do
    path = Path.join([priv_dir | relative_segments])
    if File.exists?(path), do: path
  end

  defp priv_dir_candidates do
    []
    |> append_candidate(code_priv_dir())
    |> append_candidates(ancestor_priv_dirs(File.cwd!()))
    |> append_candidates(escript_priv_dirs())
    |> Enum.uniq()
  end

  defp code_priv_dir do
    case :code.priv_dir(@app) do
      {:error, _reason} -> nil
      path -> to_string(path)
    end
  end

  defp escript_priv_dirs do
    if function_exported?(:escript, :script_name, 0) do
      :escript.script_name()
      |> to_string()
      |> case do
        "-" <> _flag -> []
        script_name -> script_name |> Path.expand() |> Path.dirname() |> ancestor_priv_dirs()
      end
    else
      []
    end
  rescue
    _error -> []
  end

  defp ancestor_priv_dirs(path) do
    path
    |> Path.expand()
    |> ancestor_dirs()
    |> Enum.map(&Path.join(&1, "priv"))
  end

  defp ancestor_dirs(path) do
    path
    |> Stream.iterate(&Path.dirname/1)
    |> Enum.reduce_while([], fn current, acc ->
      if current in acc do
        {:halt, Enum.reverse(acc)}
      else
        {:cont, [current | acc]}
      end
    end)
  end

  defp append_candidate(candidates, nil), do: candidates
  defp append_candidate(candidates, candidate), do: candidates ++ [candidate]
  defp append_candidates(candidates, more), do: candidates ++ more
end
