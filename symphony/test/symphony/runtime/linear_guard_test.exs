defmodule Symphony.Runtime.LinearGuardTest do
  use ExUnit.Case, async: true

  test "runtime source has no Linear or linear_graphql references" do
    files = Path.wildcard("lib/**/*.{ex,exs}")

    offenders =
      Enum.filter(files, fn file ->
        body = File.read!(file)
        String.contains?(body, ["Linear", "linear_graphql", "LINEAR_API_KEY"])
      end)

    assert offenders == []
  end
end
