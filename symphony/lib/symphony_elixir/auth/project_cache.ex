defmodule SymphonyElixir.Auth.ProjectCache do
  @moduledoc """
  Short-lived per-identity cache for GitLab project picker metadata.

  The cache intentionally lives in memory instead of the cookie session because
  a GitLab project list can easily exceed practical cookie limits.
  """

  @default_ttl_ms 60_000

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{} end, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec get(term()) :: {:ok, [map()]} | :miss
  def get(key), do: get(__MODULE__, key)

  @spec get(GenServer.server(), term()) :: {:ok, [map()]} | :miss
  def get(server, key) do
    now_ms = now_ms()

    Agent.get_and_update(server, fn entries ->
      entries = prune(entries, now_ms)

      case Map.get(entries, key) do
        %{expires_at_ms: expires_at_ms, projects: projects} when expires_at_ms > now_ms ->
          {{:ok, projects}, entries}

        _entry ->
          {:miss, Map.delete(entries, key)}
      end
    end)
  end

  @spec put(term(), [map()]) :: :ok
  def put(key, projects), do: put(__MODULE__, key, projects, [])

  @spec put(GenServer.server(), term(), [map()], keyword()) :: :ok
  def put(server, key, projects, opts \\ []) when is_list(projects) do
    ttl_ms = Keyword.get(opts, :ttl_ms, @default_ttl_ms)
    now_ms = now_ms()

    Agent.update(server, fn entries ->
      entries = prune(entries, now_ms)

      if ttl_ms > 0 do
        Map.put(entries, key, %{
          projects: Enum.map(projects, &Map.new/1),
          expires_at_ms: now_ms + ttl_ms
        })
      else
        Map.delete(entries, key)
      end
    end)
  end

  @spec find_project(term(), String.t() | integer()) :: {:ok, map()} | :miss
  def find_project(key, project_id), do: find_project(__MODULE__, key, project_id)

  @spec find_project(GenServer.server(), term(), String.t() | integer()) :: {:ok, map()} | :miss
  def find_project(server, key, project_id) do
    case get(server, key) do
      {:ok, projects} ->
        project_id = to_string(project_id)

        projects
        |> Enum.find(&(to_string(&1["id"] || &1[:id]) == project_id))
        |> case do
          nil -> :miss
          project -> {:ok, project}
        end

      :miss ->
        :miss
    end
  end

  defp prune(entries, now_ms) do
    Map.reject(entries, fn {_key, %{expires_at_ms: expires_at_ms}} -> expires_at_ms <= now_ms end)
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
