defmodule SymphonyElixir.Auth.ProjectCacheTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Auth.ProjectCache

  test "returns cached project lists and finds projects by id" do
    cache = start_cache()
    key = {"identity-1", "https://gitlab.example.com/api/v4"}
    projects = [%{"id" => 14, "name" => "Symphony_test"}, %{id: 8, name: "Mindshell"}]

    assert :miss = ProjectCache.get(cache, key)
    assert :ok = ProjectCache.put(cache, key, projects, ttl_ms: 1_000)

    assert {:ok, cached_projects} = ProjectCache.get(cache, key)
    assert cached_projects == [%{"id" => 14, "name" => "Symphony_test"}, %{id: 8, name: "Mindshell"}]
    assert {:ok, %{"name" => "Symphony_test"}} = ProjectCache.find_project(cache, key, "14")
    assert {:ok, %{name: "Mindshell"}} = ProjectCache.find_project(cache, key, 8)
    assert :miss = ProjectCache.find_project(cache, key, 99)
  end

  test "expires cached project lists" do
    cache = start_cache()
    key = {"identity-1", "https://gitlab.example.com/api/v4"}

    assert :ok = ProjectCache.put(cache, key, [%{"id" => 14}], ttl_ms: 1)
    Process.sleep(5)

    assert :miss = ProjectCache.get(cache, key)
  end

  defp start_cache do
    name = :"project_cache_test_#{System.unique_integer([:positive])}"
    start_supervised!({ProjectCache, name: name})
    name
  end
end
