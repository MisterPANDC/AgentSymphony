defmodule SymphonyElixir.Auth.TokenManager do
  @moduledoc """
  Opens and refreshes per-user OAuth tokens.
  """

  alias SymphonyElixir.Auth.{Config, OIDC, TokenVault}
  alias SymphonyElixir.Store

  @refresh_skew_seconds 60

  @spec access_token(String.t()) :: {:ok, String.t()} | {:error, term()}
  def access_token(identity_id) when is_binary(identity_id) do
    with %{} = token <- Store.oauth_token(identity_id),
         true <- token_current?(token) || :expired,
         {:ok, access_token} when is_binary(access_token) and access_token != "" <- TokenVault.open(token.encrypted_access_token) do
      {:ok, access_token}
    else
      :expired -> refresh_access_token(identity_id)
      nil -> {:error, :oauth_token_not_found}
      {:ok, _} -> {:error, :missing_access_token}
      {:error, reason} -> {:error, reason}
    end
  end

  def access_token(_identity_id), do: {:error, :missing_identity_id}

  defp refresh_access_token(identity_id) do
    with %{} = token <- Store.oauth_token(identity_id),
         {:ok, refresh_token} when is_binary(refresh_token) <- TokenVault.open(token.encrypted_refresh_token),
         {:ok, config} <- Config.load(),
         {:ok, discovery} <- OIDC.discovery(config),
         {:ok, response} <- OIDC.refresh_token(config, discovery, refresh_token),
         updated <- Store.upsert_oauth_token(identity_id, response),
         {:ok, access_token} when is_binary(access_token) and access_token != "" <- TokenVault.open(updated.encrypted_access_token) do
      {:ok, access_token}
    else
      nil -> {:error, :oauth_token_not_found}
      {:ok, nil} -> {:error, :missing_refresh_token}
      {:ok, _} -> {:error, :missing_access_token}
      {:error, reason} -> {:error, reason}
    end
  end

  defp token_current?(%{expires_at: %DateTime{} = expires_at}) do
    DateTime.compare(expires_at, DateTime.utc_now() |> DateTime.add(@refresh_skew_seconds, :second)) == :gt
  end

  defp token_current?(_token), do: true
end
