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

  test "requires OIDC settings by default" do
    assert {:error, {:missing_oidc_config, missing}} = Config.load(load_env_file: false)
    assert missing =~ "GITLAB_OIDC_ISSUER or GITLAB_BASE_URL"
    assert missing =~ "GITLAB_OIDC_CLIENT_ID"
    assert missing =~ "GITLAB_OIDC_CLIENT_SECRET"
  end

  test "validates required OIDC settings" do
    System.put_env("SYMPHONY_AUTH_MODE", "gitlab_oidc")

    assert {:error, {:missing_oidc_config, missing}} = Config.load(load_env_file: false)
    assert missing =~ "GITLAB_OIDC_ISSUER or GITLAB_BASE_URL"
    assert missing =~ "GITLAB_OIDC_CLIENT_ID"
    assert missing =~ "GITLAB_OIDC_CLIENT_SECRET"
  end

  test "rejects unsupported auth modes" do
    System.put_env("SYMPHONY_AUTH_MODE", "password")

    assert {:error, {:unsupported_auth_mode, "password"}} = Config.load(load_env_file: false)
  end

  test "builds OIDC config from GitLab base URL" do
    System.put_env("GITLAB_BASE_URL", "https://gitlab.example.com/")
    System.put_env("GITLAB_OIDC_CLIENT_ID", "client-id")
    System.put_env("GITLAB_OIDC_CLIENT_SECRET", "client-secret")
    System.put_env("SYMPHONY_PUBLIC_URL", "https://symphony.example.com/")

    assert {:ok, config} = Config.load(load_env_file: false)
    assert Config.oidc_enabled?(config)
    assert config.issuer == "https://gitlab.example.com"
    assert config.redirect_uri == "https://symphony.example.com/auth/gitlab/callback"
    assert config.scopes == ~w(openid profile email api)
  end

  test "maps GitLab access levels to roles" do
    assert Config.role_for_access_level(20) == "Reporter"
    assert Config.role_for_access_level(30) == "Developer"
    assert Config.role_for_access_level(40) == "Maintainer"
    assert Config.role_for_access_level(50) == "Owner"
  end
end
