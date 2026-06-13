defmodule SymphonyElixir.Auth.ConfigTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Auth.Config

  @envs ~w(
    SYMPHONY_AUTH_MODE
    GITLAB_OIDC_ISSUER
    GITLAB_OIDC_CLIENT_ID
    GITLAB_OIDC_CLIENT_SECRET
    GITLAB_OIDC_SCOPES
    SYMPHONY_PUBLIC_URL
    GITLAB_BASE_URL
    GITLAB_PROJECT_API_URL
  )

  setup do
    previous = Map.new(@envs, &{&1, System.get_env(&1)})

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)

    Enum.each(@envs, &System.delete_env/1)
    :ok
  end

  test "defaults to local single-user mode" do
    assert {:ok, config} = Config.load(load_env_file: false)
    refute Config.oidc_enabled?(config)
    assert Config.local_user().access_level == 50
  end

  test "validates required OIDC settings" do
    System.put_env("SYMPHONY_AUTH_MODE", "gitlab_oidc")

    assert {:error, {:missing_oidc_config, missing}} = Config.load(load_env_file: false)
    assert missing =~ "GITLAB_OIDC_CLIENT_ID"
    assert missing =~ "GITLAB_OIDC_CLIENT_SECRET"
  end

  test "builds OIDC config from GitLab project API URL" do
    System.put_env("SYMPHONY_AUTH_MODE", "gitlab_oidc")
    System.put_env("GITLAB_PROJECT_API_URL", "https://gitlab.example.com/api/v4/projects/group%2Frepo")
    System.put_env("GITLAB_OIDC_CLIENT_ID", "client-id")
    System.put_env("GITLAB_OIDC_CLIENT_SECRET", "client-secret")
    System.put_env("SYMPHONY_PUBLIC_URL", "https://symphony.example.com/")
    System.put_env("GITLAB_OIDC_SCOPES", "openid,profile,email,read_api")

    assert {:ok, config} = Config.load(load_env_file: false)
    assert Config.oidc_enabled?(config)
    assert config.issuer == "https://gitlab.example.com"
    assert config.redirect_uri == "https://symphony.example.com/auth/gitlab/callback"
    assert config.scopes == ~w(openid profile email read_api)
  end

  test "maps GitLab access levels to roles" do
    assert Config.role_for_access_level(20) == "Reporter"
    assert Config.role_for_access_level(30) == "Developer"
    assert Config.role_for_access_level(40) == "Maintainer"
    assert Config.role_for_access_level(50) == "Owner"
  end
end
