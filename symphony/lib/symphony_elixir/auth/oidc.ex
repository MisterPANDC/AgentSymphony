defmodule SymphonyElixir.Auth.OIDC do
  @moduledoc """
  GitLab OIDC client helpers.
  """

  alias SymphonyElixir.Auth.{Config, JWT}

  @timeout_ms 30_000

  @spec discovery(Config.t()) :: {:ok, map()} | {:error, term()}
  def discovery(%Config{issuer: issuer}) do
    request(:get, String.trim_trailing(issuer, "/") <> "/.well-known/openid-configuration")
  end

  @spec authorize_url(Config.t(), map(), String.t(), String.t(), String.t()) :: String.t()
  def authorize_url(%Config{} = config, discovery, state, nonce, code_challenge) do
    params =
      URI.encode_query(%{
        "client_id" => config.client_id,
        "redirect_uri" => config.redirect_uri,
        "response_type" => "code",
        "scope" => Enum.join(config.scopes, " "),
        "state" => state,
        "nonce" => nonce,
        "code_challenge" => code_challenge,
        "code_challenge_method" => "S256"
      })

    discovery["authorization_endpoint"] <> "?" <> params
  end

  @spec exchange_code(Config.t(), map(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def exchange_code(%Config{} = config, discovery, code, code_verifier) do
    request(:post, discovery["token_endpoint"],
      form: %{
        "grant_type" => "authorization_code",
        "code" => code,
        "redirect_uri" => config.redirect_uri,
        "client_id" => config.client_id,
        "client_secret" => config.client_secret,
        "code_verifier" => code_verifier
      }
    )
  end

  @spec refresh_token(Config.t(), map(), String.t()) :: {:ok, map()} | {:error, term()}
  def refresh_token(%Config{} = config, discovery, refresh_token) do
    request(:post, discovery["token_endpoint"],
      form: %{
        "grant_type" => "refresh_token",
        "refresh_token" => refresh_token,
        "client_id" => config.client_id,
        "client_secret" => config.client_secret
      }
    )
  end

  @spec userinfo(map(), String.t()) :: {:ok, map()} | {:error, term()}
  def userinfo(discovery, access_token) do
    request(:get, discovery["userinfo_endpoint"], auth: {:bearer, access_token})
  end

  @spec verify_id_token(Config.t(), map(), String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def verify_id_token(%Config{} = config, discovery, id_token, nonce) do
    with {:ok, jwks} <- request(:get, discovery["jwks_uri"]) do
      JWT.verify_rs256(id_token, jwks,
        issuer: config.issuer,
        audience: config.client_id,
        nonce: nonce
      )
    end
  end

  @spec code_challenge(String.t()) :: String.t()
  def code_challenge(verifier) when is_binary(verifier) do
    :crypto.hash(:sha256, verifier)
    |> Base.url_encode64(padding: false)
  end

  @spec random_url_token(pos_integer()) :: String.t()
  def random_url_token(bytes \\ 32), do: bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  defp request(method, url, opts \\ [])

  defp request(method, url, opts) when is_binary(url) do
    req_opts =
      opts
      |> Keyword.merge(method: method, url: url, receive_timeout: @timeout_ms)
      |> Keyword.merge(req_extra_options())

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:oidc_http_error, status, body}}

      {:error, reason} ->
        {:error, {:oidc_request_failed, reason}}
    end
  end

  defp request(_method, _url, _opts), do: {:error, :missing_oidc_endpoint}

  defp req_extra_options do
    Application.get_env(:symphony_elixir, :oidc_req_options, [])
  end
end
