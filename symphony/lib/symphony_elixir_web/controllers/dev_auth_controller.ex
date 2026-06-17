defmodule SymphonyElixirWeb.DevAuthController do
  @moduledoc false

  use Phoenix.Controller, formats: [:html, :json]

  import Plug.Conn

  alias SymphonyElixir.Store

  @enabled_envs [:dev, :test]

  @spec login(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def login(conn, _params) do
    if Mix.env() in @enabled_envs do
      project = ensure_project()

      conn
      |> put_session(:current_user, dev_user(project))
      |> redirect(to: "/")
    else
      conn
      |> put_status(:not_found)
      |> text("Not found")
    end
  end

  defp ensure_project do
    Store.upsert_project(%{
      api_root: "https://gitlab.example.test/api/v4",
      project_ref: "agent/symphony-dev",
      project_id: 999_001,
      path_with_namespace: "agent/symphony-dev",
      name: "Symphony Dev",
      web_url: "https://gitlab.example.test/agent/symphony-dev",
      visibility: "private",
      read_only: false,
      automation_credential_mode: "project_access_token"
    })
  end

  defp dev_user(project) do
    %{
      identity_id: "dev-auth",
      project_membership_id: "dev-membership",
      project_setting_id: project.id,
      provider: "gitlab",
      issuer: "dev",
      gitlab_user_id: "999001",
      username: "dev",
      name: "Dev User",
      email: "dev@example.test",
      avatar_url: nil,
      profile_url: nil,
      access_level: 50,
      membership_checked_at: System.system_time(:second)
    }
  end
end
