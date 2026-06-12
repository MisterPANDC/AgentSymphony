defmodule SymphonyElixir.Dotenv do
  @moduledoc """
  Minimal `.env.local` loader for local single-user runtime.

  Values already present in the process environment win, so shell-provided
  secrets can override the local file without rewriting it.
  """

  @spec load(Path.t()) :: :ok
  def load(path \\ ".env.local") do
    path
    |> Path.expand()
    |> File.read()
    |> case do
      {:ok, contents} ->
        contents
        |> String.split(["\n", "\r\n"], trim: false)
        |> Enum.each(&load_line/1)

      {:error, :enoent} ->
        :ok

      {:error, _reason} ->
        :ok
    end
  end

  defp load_line(line) do
    line = String.trim(line)

    cond do
      line == "" or String.starts_with?(line, "#") ->
        :ok

      true ->
        case String.split(line, "=", parts: 2) do
          [key, value] ->
            key = String.trim(key)

            if valid_key?(key) and is_nil(System.get_env(key)) do
              System.put_env(key, unquote_value(String.trim(value)))
            end

          _ ->
            :ok
        end
    end
  end

  defp valid_key?(key), do: String.match?(key, ~r/^[A-Za-z_][A-Za-z0-9_]*$/)

  defp unquote_value("\"" <> rest) do
    if String.ends_with?(rest, "\"") do
      rest |> String.trim_trailing("\"") |> String.replace(~S(\"), ~S("))
    else
      "\"" <> rest
    end
  end

  defp unquote_value("'" <> rest) do
    if String.ends_with?(rest, "'"), do: String.trim_trailing(rest, "'"), else: "'" <> rest
  end

  defp unquote_value(value), do: value
end
