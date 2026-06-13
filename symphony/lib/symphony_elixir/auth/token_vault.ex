defmodule SymphonyElixir.Auth.TokenVault do
  @moduledoc """
  Small AES-GCM token vault for OAuth and Project Access Tokens.

  The encrypted values are safe to return to neither UI nor logs; API responses
  should expose only configured/missing status.
  """

  @aad "symphony-token-v1"
  @iv_bytes 12
  @tag_bytes 16

  @spec seal(String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def seal(nil), do: {:ok, nil}
  def seal(""), do: {:ok, nil}

  def seal(value) when is_binary(value) do
    with {:ok, key} <- key() do
      iv = :crypto.strong_rand_bytes(@iv_bytes)
      {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, value, @aad, @tag_bytes, true)
      {:ok, "v1:" <> Base.url_encode64(iv <> tag <> ciphertext, padding: false)}
    end
  end

  @spec open(String.t() | nil) :: {:ok, String.t() | nil} | {:error, term()}
  def open(nil), do: {:ok, nil}

  def open("v1:" <> encoded) do
    with {:ok, key} <- key(),
         {:ok, sealed} <- Base.url_decode64(encoded, padding: false),
         <<iv::binary-size(@iv_bytes), tag::binary-size(@tag_bytes), ciphertext::binary>> <- sealed,
         plaintext when is_binary(plaintext) <-
           :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
      {:ok, plaintext}
    else
      :error -> {:error, :invalid_token_ciphertext}
      _ -> {:error, :token_decrypt_failed}
    end
  end

  def open(_value), do: {:error, :unsupported_token_ciphertext}

  defp key do
    case token_secret() do
      nil -> {:error, :missing_token_encryption_secret}
      secret -> {:ok, :crypto.hash(:sha256, secret)}
    end
  end

  defp token_secret do
    System.get_env("SYMPHONY_TOKEN_ENCRYPTION_SECRET") ||
      System.get_env("SYMPHONY_SESSION_SECRET") ||
      System.get_env("SECRET_KEY_BASE")
  end
end
