defmodule SymphonyElixir.Config.SchemaTest do
  use ExUnit.Case, async: false

  alias SymphonyElixir.Config.Schema

  setup do
    previous_home = System.get_env("SYMPHONY_HOME")

    on_exit(fn ->
      case previous_home do
        nil -> System.delete_env("SYMPHONY_HOME")
        value -> System.put_env("SYMPHONY_HOME", value)
      end
    end)

    System.delete_env("SYMPHONY_HOME")
    :ok
  end

  test "defaults Symphony home to ~/.symphony" do
    assert {:ok, settings} = Schema.parse(%{})
    assert settings.home == Path.expand("~/.symphony")
  end

  test "reads Symphony home from SYMPHONY_HOME" do
    home = Path.join(System.tmp_dir!(), "symphony-home-#{System.unique_integer([:positive])}")
    System.put_env("SYMPHONY_HOME", home)

    assert {:ok, settings} = Schema.parse(%{})
    assert settings.home == Path.expand(home)
  end

  test "allows explicit home config to override SYMPHONY_HOME" do
    env_home = Path.join(System.tmp_dir!(), "symphony-env-home")
    configured_home = Path.join(System.tmp_dir!(), "symphony-configured-home")
    System.put_env("SYMPHONY_HOME", env_home)

    assert {:ok, settings} = Schema.parse(%{"home" => configured_home})
    assert settings.home == Path.expand(configured_home)
  end
end
