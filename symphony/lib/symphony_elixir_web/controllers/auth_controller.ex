defmodule SymphonyElixirWeb.AuthController do
  use Phoenix.Controller, formats: [:html, :json]

  import Plug.Conn

  alias Symphony.GitLab.Error
  alias SymphonyElixir.Auth.{Config, OIDC}
  alias SymphonyElixir.Store
  alias SymphonyElixirWeb.AuthPlug

  @spec session(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def session(conn, _params) do
    config = conn.assigns[:auth_config]
    user = AuthPlug.current_user(conn)

    json(conn, %{
      auth: %{
        mode: config && config.mode,
        enabled: config && Config.oidc_enabled?(config),
        loginUrl: "/auth/gitlab",
        logoutUrl: "/auth/logout"
      },
      user: user && public_user(user),
      permissions: permissions(user, config),
      project: session_project(user)
    })
  end

  @spec login(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def login(conn, params) do
    with {:ok, config} <- Config.load(),
         true <- Config.oidc_enabled?(config) || :auth_disabled,
         {:ok, discovery} <- OIDC.discovery(config) do
      state = OIDC.random_url_token()
      nonce = OIDC.random_url_token()
      verifier = OIDC.random_url_token(48)
      challenge = OIDC.code_challenge(verifier)

      conn
      |> put_session(:oidc_state, state)
      |> put_session(:oidc_nonce, nonce)
      |> put_session(:oidc_verifier, verifier)
      |> put_session(:oidc_return_to, normalize_return_to(params["return_to"]))
      |> redirect(external: OIDC.authorize_url(config, discovery, state, nonce, challenge))
    else
      :auth_disabled ->
        redirect(conn, to: "/")

      {:error, reason} ->
        auth_failure(conn, 500, "GitLab sign-in is not configured", inspect(reason))
    end
  end

  @spec callback(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def callback(conn, %{"code" => code, "state" => state}) do
    with :ok <- verify_state(conn, state),
         {:ok, config} <- Config.load(),
         {:ok, discovery} <- OIDC.discovery(config),
         {:ok, token_response} <- OIDC.exchange_code(config, discovery, code, get_session(conn, :oidc_verifier)),
         id_token when is_binary(id_token) <- token_response["id_token"] || {:error, :missing_id_token},
         access_token when is_binary(access_token) <- token_response["access_token"] || {:error, :missing_access_token},
         {:ok, claims} <- OIDC.verify_id_token(config, discovery, id_token, get_session(conn, :oidc_nonce)),
         {:ok, userinfo} <- OIDC.userinfo(discovery, access_token) do
      identity = Store.upsert_gitlab_identity(identity_attrs(config, claims, userinfo))
      Store.upsert_oauth_token(identity.id, token_response)
      return_to = get_session(conn, :oidc_return_to) || "/"

      conn
      |> configure_session(renew: true)
      |> delete_oidc_session()
      |> put_session(:current_user, session_user(identity))
      |> redirect(to: return_to)
    else
      {:error, :invalid_oidc_state} ->
        auth_failure(conn, 400, "Sign-in session expired", "Start GitLab sign-in again.")

      {:error, %Error{} = error} ->
        auth_failure(conn, 502, "GitLab validation failed", error.message)

      {:error, reason} ->
        auth_failure(conn, 502, "GitLab sign-in failed", inspect(reason))
    end
  end

  def callback(conn, %{"error" => error} = params) do
    detail = params["error_description"] || error
    auth_failure(conn, 400, "GitLab rejected sign-in", detail)
  end

  def callback(conn, _params), do: auth_failure(conn, 400, "Invalid sign-in callback", "GitLab did not return an authorization code.")

  @spec logout(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def logout(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  defp verify_state(conn, state) do
    if is_binary(state) and state == get_session(conn, :oidc_state), do: :ok, else: {:error, :invalid_oidc_state}
  end

  defp identity_attrs(config, claims, userinfo) do
    username =
      first_present([
        userinfo["nickname"],
        userinfo["preferred_username"],
        claims["nickname"],
        claims["preferred_username"],
        claims["username"],
        claims["sub"]
      ])

    %{
      issuer: config.issuer,
      gitlab_user_id: to_string(claims["sub"]),
      sub: to_string(claims["sub"]),
      username: username,
      name: first_present([userinfo["name"], claims["name"], username]),
      email: first_present([userinfo["email"], claims["email"]]),
      avatar_url: first_present([userinfo["picture"], claims["picture"]]),
      profile_url: first_present([userinfo["profile"], claims["profile"]]),
      raw_claims: %{"id_token" => claims, "userinfo" => userinfo}
    }
  end

  defp session_user(identity) do
    %{
      identity_id: identity.id,
      project_membership_id: nil,
      project_setting_id: nil,
      provider: "gitlab",
      issuer: identity.issuer,
      gitlab_user_id: identity.gitlab_user_id,
      username: identity.username,
      name: identity.name || identity.username,
      email: identity.email,
      avatar_url: identity.avatar_url,
      profile_url: identity.profile_url,
      access_level: 0,
      role: "No access",
      membership_checked_at: System.system_time(:second),
      local?: false
    }
  end

  defp public_user(user) do
    %{
      provider: user[:provider],
      issuer: user[:issuer],
      gitlab_user_id: user[:gitlab_user_id],
      username: user[:username],
      name: user[:name],
      email: user[:email],
      avatar_url: user[:avatar_url],
      profile_url: user[:profile_url],
      access_level: user[:access_level],
      role: user[:role],
      project_setting_id: user[:project_setting_id],
      local: user[:local?] == true
    }
  end

  defp permissions(nil, %Config{} = config) do
    %{read: false, write: false, admin: false, requiredAccessLevel: config.min_access_level}
  end

  defp permissions(%{} = user, %Config{} = config) do
    access_level = Map.get(user, :access_level, 0)

    %{
      read: access_level >= config.min_access_level,
      write: access_level >= config.write_access_level,
      admin: access_level >= config.admin_access_level,
      requiredAccessLevel: config.min_access_level,
      writeAccessLevel: config.write_access_level,
      adminAccessLevel: config.admin_access_level
    }
  end

  defp permissions(_user, _config), do: %{read: false, write: false, admin: false}

  defp session_project(%{project_setting_id: project_setting_id}) when is_binary(project_setting_id),
    do: Store.project_by_id(project_setting_id)

  defp session_project(%{local?: true}), do: Store.project()
  defp session_project(_user), do: nil

  defp delete_oidc_session(conn) do
    conn
    |> delete_session(:oidc_state)
    |> delete_session(:oidc_nonce)
    |> delete_session(:oidc_verifier)
    |> delete_session(:oidc_return_to)
  end

  defp normalize_return_to(path) when is_binary(path) do
    uri = URI.parse(path)

    cond do
      uri.scheme || uri.host -> "/"
      String.starts_with?(path, "/auth/") -> "/"
      String.starts_with?(path, "/") -> path
      true -> "/"
    end
  end

  defp normalize_return_to(_path), do: "/"

  defp first_present(values) do
    Enum.find(values, fn
      value when is_binary(value) -> String.trim(value) != ""
      value -> not is_nil(value)
    end)
  end

  defp auth_failure(conn, status, title, detail) do
    conn
    |> put_status(status)
    |> put_resp_content_type("text/html")
    |> send_resp(status, failure_html(title, detail))
  end

  defp failure_html(title, detail) do
    escaped_title = Phoenix.HTML.html_escape(title) |> Phoenix.HTML.safe_to_string()
    escaped_detail = Phoenix.HTML.html_escape(detail) |> Phoenix.HTML.safe_to_string()

    """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>#{escaped_title}</title>
        <style>
          :root { color: #1d1d1f; background: #f7f8fa; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
          body { margin: 0; min-height: 100vh; display: grid; place-items: center; }
          main { width: min(440px, calc(100vw - 32px)); border: 1px solid #dedfe4; border-radius: 8px; background: #fff; box-shadow: 0 16px 40px rgba(17,24,39,.08); padding: 24px; }
          h1 { margin: 0; font-size: 18px; line-height: 26px; }
          p { color: #686b73; font-size: 14px; line-height: 21px; }
          a { display: inline-flex; height: 32px; align-items: center; border: 1px solid #dedfe4; border-radius: 6px; padding: 0 11px; color: #1d1d1f; text-decoration: none; background: #fff; }
        </style>
      </head>
      <body>
        <main>
          <h1>#{escaped_title}</h1>
          <p>#{escaped_detail}</p>
          <a href="/">Return to Symphony</a>
        </main>
      </body>
    </html>
    """
  end
end
