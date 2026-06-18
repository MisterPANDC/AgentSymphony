defmodule SymphonyElixir.PrivAssetsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.PrivAssets

  test "finds the agent MCP installer from the source checkout" do
    assert {:ok, script} = PrivAssets.agent_mcp_install_script()
    assert Path.basename(script) == "install.sh"
    assert File.exists?(script)
    assert File.regular?(script)
  end
end
