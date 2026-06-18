defmodule SymphonyElixir.AgentAssetRegistry do
  @moduledoc false

  alias SymphonyElixir.Config

  @legacy_file_name "agent-assets.json"
  @skill_file_name "agent-skill.json"
  @plugin_file_name "agent-plugin.json"
  @asset_kinds ~w(skills plugins)

  @spec path() :: Path.t()
  def path, do: legacy_path()

  @spec skill_path() :: Path.t()
  def skill_path, do: Path.join(Config.settings!().home, @skill_file_name)

  @spec plugin_path() :: Path.t()
  def plugin_path, do: Path.join(Config.settings!().home, @plugin_file_name)

  @spec legacy_path() :: Path.t()
  def legacy_path, do: Path.join(Config.settings!().home, @legacy_file_name)

  @spec list_skills() :: {:ok, map()} | {:error, term()}
  def list_skills, do: list_assets("skills")

  @spec list_plugins() :: {:ok, map()} | {:error, term()}
  def list_plugins, do: list_assets("plugins")

  @spec list_assets(String.t()) :: {:ok, map()} | {:error, term()}
  def list_assets(kind) when kind in @asset_kinds do
    case read_registry() do
      {:ok, registry} -> {:ok, Map.get(registry, kind, %{})}
      {:error, :enoent} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec selected_agent_assets([String.t()], [String.t()]) :: {:ok, map(), map()} | {:error, term()}
  def selected_agent_assets(skill_names, plugin_names) do
    with {:ok, skills} <- selected_assets("skills", skill_names),
         {:ok, plugins} <- selected_assets("plugins", plugin_names) do
      {:ok, skills, plugins}
    end
  end

  @spec selected_assets(String.t(), [String.t()]) :: {:ok, map()} | {:error, term()}
  def selected_assets(kind, names) when kind in @asset_kinds and is_list(names) do
    with {:ok, assets} <- list_assets(kind) do
      selected =
        names
        |> Enum.map(&to_string/1)
        |> Enum.uniq()
        |> Map.new(fn name -> {name, Map.get(assets, name)} end)

      case Enum.find(selected, fn {_name, asset} -> is_nil(asset) end) do
        {name, nil} -> {:error, {:unknown_agent_asset, kind, name}}
        nil -> {:ok, selected}
      end
    end
  end

  @spec put_registry(map()) :: {:ok, map()} | {:error, term()}
  def put_registry(attrs) when is_map(attrs) do
    attrs = stringify_keys(attrs)

    with {:ok, skills} <- normalize_assets(Map.get(attrs, "skills", %{})),
         {:ok, plugins} <- normalize_assets(Map.get(attrs, "plugins", %{})),
         registry <- %{"skills" => skills, "plugins" => plugins},
         :ok <- write_registry(registry) do
      {:ok, registry}
    end
  end

  @spec dto() :: {:ok, map()} | {:error, term()}
  def dto do
    case read_registry() do
      {:ok, registry} -> {:ok, registry_dto(registry)}
      {:error, :enoent} -> {:ok, registry_dto(%{"skills" => %{}, "plugins" => %{}})}
      {:error, reason} -> {:error, reason}
    end
  end

  defp read_registry do
    case {read_asset_file("skills", skill_path()), read_asset_file("plugins", plugin_path())} do
      {{:ok, skills}, {:ok, plugins}} ->
        {:ok, %{"skills" => skills, "plugins" => plugins}}

      {{:error, :enoent}, {:error, :enoent}} ->
        read_legacy_registry()

      {{:error, :enoent}, {:ok, plugins}} ->
        {:ok, %{"skills" => legacy_assets("skills"), "plugins" => plugins}}

      {{:ok, skills}, {:error, :enoent}} ->
        {:ok, %{"skills" => skills, "plugins" => legacy_assets("plugins")}}

      {{:error, reason}, _} ->
        {:error, reason}

      {_, {:error, reason}} ->
        {:error, reason}
    end
  end

  defp read_asset_file(kind, path) do
    case File.read(path) do
      {:ok, contents} ->
        with {:ok, decoded} <- Jason.decode(contents),
             {:ok, assets} <- normalize_asset_file(kind, decoded) do
          {:ok, assets}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_legacy_registry do
    case File.read(legacy_path()) do
      {:ok, contents} ->
        with {:ok, decoded} <- Jason.decode(contents),
             {:ok, registry} <- normalize_registry(decoded) do
          {:ok, registry}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp legacy_assets(kind) do
    case read_legacy_registry() do
      {:ok, registry} -> Map.get(registry, kind, %{})
      _ -> %{}
    end
  end

  defp normalize_asset_file(kind, file) when kind in @asset_kinds and is_map(file) do
    file = stringify_keys(file)
    normalize_assets(Map.get(file, kind, file))
  end

  defp normalize_asset_file(_kind, _file), do: {:error, :invalid_agent_asset_registry}

  defp normalize_registry(registry) when is_map(registry) do
    registry = stringify_keys(registry)

    with {:ok, skills} <- normalize_assets(Map.get(registry, "skills", %{})),
         {:ok, plugins} <- normalize_assets(Map.get(registry, "plugins", %{})) do
      {:ok, %{"skills" => skills, "plugins" => plugins}}
    end
  end

  defp normalize_registry(_registry), do: {:error, :invalid_agent_asset_registry}

  defp write_registry(registry) do
    with :ok <- write_asset_file(skill_path(), Map.get(registry, "skills", %{})),
         :ok <- write_asset_file(plugin_path(), Map.get(registry, "plugins", %{})) do
      :ok
    end
  end

  defp write_asset_file(path, assets) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, encoded} <- Jason.encode(assets, pretty: true) do
      File.write(path, encoded <> "\n")
    end
  end

  defp registry_dto(registry) do
    %{
      path: legacy_path(),
      skillPath: skill_path(),
      pluginPath: plugin_path(),
      skills: Map.get(registry, "skills", %{}),
      plugins: Map.get(registry, "plugins", %{})
    }
  end

  defp normalize_assets(assets) when is_map(assets) do
    Enum.reduce_while(assets, {:ok, %{}}, fn {name, attrs}, {:ok, acc} ->
      name = to_string(name)

      case normalize_asset(name, attrs) do
        {:ok, asset} -> {:cont, {:ok, Map.put(acc, name, asset)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp normalize_assets(_assets), do: {:error, :invalid_agent_asset_registry}

  defp normalize_asset(_name, attrs) when not is_map(attrs), do: {:error, :invalid_agent_asset_definition}

  defp normalize_asset(name, attrs) do
    attrs = stringify_keys(attrs)
    path = attrs["path"]
    git_url = attrs["git_url"]
    content = attrs["content"]
    filename = attrs["filename"]

    cond do
      not valid_name?(name) ->
        {:error, :invalid_agent_asset_name}

      is_binary(path) and String.trim(path) != "" ->
        {:ok, %{"path" => Path.expand(String.trim(path))}}

      is_binary(git_url) and String.trim(git_url) != "" ->
        {:ok, %{"git_url" => String.trim(git_url)}}

      is_binary(content) and String.trim(content) != "" ->
        asset = %{"content" => content}
        asset = if is_binary(filename) and String.trim(filename) != "", do: Map.put(asset, "filename", Path.basename(String.trim(filename))), else: asset
        {:ok, asset}

      true ->
        {:error, :invalid_agent_asset_path}
    end
  end

  defp stringify_keys(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp valid_name?(name), do: is_binary(name) and Regex.match?(~r/^[A-Za-z0-9_.-]+$/, name)
end
