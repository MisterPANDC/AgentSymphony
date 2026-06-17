defmodule SymphonyElixir.AgentMcpRegistry do
  @moduledoc false

  alias SymphonyElixir.Config

  @file_name "agent-mcp.json"

  @spec path() :: Path.t()
  def path, do: Path.join(Config.settings!().home, @file_name)

  @spec list_servers() :: {:ok, map()} | {:error, term()}
  def list_servers do
    case read_registry() do
      {:ok, %{"mcpServers" => servers}} when is_map(servers) -> {:ok, servers}
      {:ok, _registry} -> {:ok, %{}}
      {:error, :enoent} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec selected_servers([String.t()]) :: {:ok, map()} | {:error, term()}
  def selected_servers(names) when is_list(names) do
    with {:ok, servers} <- list_servers() do
      selected =
        names
        |> Enum.map(&to_string/1)
        |> Enum.uniq()
        |> Map.new(fn name -> {name, Map.get(servers, name)} end)

      case Enum.find(selected, fn {_name, server} -> is_nil(server) end) do
        {name, nil} -> {:error, {:unknown_mcp_server, name}}
        nil -> {:ok, selected}
      end
    end
  end

  @spec put_server(map()) :: {:ok, map()} | {:error, term()}
  def put_server(attrs) when is_map(attrs) do
    with {:ok, name, server} <- normalize_server(attrs),
         {:ok, registry} <- read_or_empty(),
         servers <- Map.get(registry, "mcpServers", %{}),
         registry <- Map.put(registry, "mcpServers", Map.put(servers, name, server)),
         :ok <- write_registry(registry) do
      {:ok, registry}
    end
  end

  @spec put_registry(map()) :: {:ok, map()} | {:error, term()}
  def put_registry(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with %{} = servers <- Map.get(attrs, "mcpServers") || {:error, :invalid_mcp_registry},
         {:ok, servers} <- normalize_servers(servers),
         registry <- %{"mcpServers" => servers},
         :ok <- write_registry(registry) do
      {:ok, registry}
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_mcp_registry}
    end
  end

  @spec dto() :: {:ok, map()} | {:error, term()}
  def dto do
    with {:ok, servers} <- list_servers() do
      {:ok, %{path: path(), mcpServers: servers}}
    end
  end

  defp read_or_empty do
    case read_registry() do
      {:ok, registry} -> {:ok, registry}
      {:error, :enoent} -> {:ok, %{"mcpServers" => %{}}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_registry do
    case File.read(path()) do
      {:ok, contents} -> Jason.decode(contents)
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_registry(registry) do
    registry = Map.put(registry, "mcpServers", Map.get(registry, "mcpServers", %{}))

    with :ok <- File.mkdir_p(Path.dirname(path())),
         {:ok, encoded} <- Jason.encode(registry, pretty: true) do
      File.write(path(), encoded <> "\n")
    end
  end

  defp normalize_server(attrs) do
    attrs = stringify_keys(attrs)
    name = attrs["name"]

    with {:ok, server} <- normalize_named_server(name, attrs) do
      {:ok, name, server}
    end
  end

  defp normalize_servers(servers) do
    Enum.reduce_while(servers, {:ok, %{}}, fn {name, attrs}, {:ok, acc} ->
      name = to_string(name)

      case normalize_named_server(name, attrs) do
        {:ok, server} -> {:cont, {:ok, Map.put(acc, name, server)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_named_server(_name, attrs) when not is_map(attrs), do: {:error, :invalid_mcp_server_definition}

  defp normalize_named_server(name, attrs) do
    attrs = stringify_keys(attrs)
    command = attrs["command"]
    args = Map.get(attrs, "args", [])
    env = Map.get(attrs, "env", %{})
    startup_timeout_sec = attrs["startup_timeout_sec"] || attrs["startupTimeoutSec"]

    cond do
      not valid_name?(name) ->
        {:error, :invalid_mcp_server_name}

      not is_binary(command) or String.trim(command) == "" ->
        {:error, :invalid_mcp_server_command}

      not valid_string_list?(args) ->
        {:error, :invalid_mcp_server_args}

      not valid_string_map?(env) ->
        {:error, :invalid_mcp_server_env}

      not is_nil(startup_timeout_sec) and (not is_integer(startup_timeout_sec) or startup_timeout_sec <= 0) ->
        {:error, :invalid_mcp_server_startup_timeout}

      true ->
        server =
          %{
            "command" => String.trim(command),
            "args" => args,
            "env" => env
          }
          |> maybe_put("startup_timeout_sec", startup_timeout_sec)

        {:ok, server}
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp valid_name?(name), do: is_binary(name) and Regex.match?(~r/^[A-Za-z0-9_.-]+$/, name)
  defp valid_string_list?(values), do: is_list(values) and Enum.all?(values, &is_binary/1)

  defp valid_string_map?(map) do
    is_map(map) and Enum.all?(map, fn {key, value} -> is_binary(key) and is_binary(value) end)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
