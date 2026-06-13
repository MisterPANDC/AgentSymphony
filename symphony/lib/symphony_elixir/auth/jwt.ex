defmodule SymphonyElixir.Auth.JWT do
  @moduledoc """
  Minimal RS256 JWT verifier for GitLab OIDC ID tokens.
  """

  @skew_seconds 60

  @spec verify_rs256(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify_rs256(token, jwks, opts) when is_binary(token) and is_map(jwks) do
    with {:ok, header, claims, signing_input, signature} <- decode(token),
         :ok <- require_alg(header),
         {:ok, jwk} <- find_jwk(jwks, header["kid"]),
         :ok <- verify_signature(jwk, signing_input, signature),
         :ok <- validate_claims(claims, opts) do
      {:ok, claims}
    end
  end

  def verify_rs256(_token, _jwks, _opts), do: {:error, :invalid_token}

  defp decode(token) do
    case String.split(token, ".") do
      [encoded_header, encoded_claims, encoded_signature] ->
        with {:ok, header} <- decode_json(encoded_header),
             {:ok, claims} <- decode_json(encoded_claims),
             {:ok, signature} <- Base.url_decode64(encoded_signature, padding: false) do
          {:ok, header, claims, encoded_header <> "." <> encoded_claims, signature}
        end

      _ ->
        {:error, :invalid_token_segments}
    end
  end

  defp decode_json(segment) do
    with {:ok, binary} <- Base.url_decode64(segment, padding: false),
         {:ok, decoded} <- Jason.decode(binary) do
      {:ok, decoded}
    else
      _ -> {:error, :invalid_token_json}
    end
  end

  defp require_alg(%{"alg" => "RS256"}), do: :ok
  defp require_alg(_header), do: {:error, :unsupported_jwt_alg}

  defp find_jwk(%{"keys" => keys}, kid) when is_list(keys) and is_binary(kid) do
    case Enum.find(keys, &(&1["kid"] == kid)) do
      nil -> {:error, :jwk_not_found}
      jwk -> {:ok, jwk}
    end
  end

  defp find_jwk(_jwks, _kid), do: {:error, :invalid_jwks}

  defp verify_signature(%{"kty" => "RSA", "n" => n, "e" => e}, signing_input, signature) do
    with {:ok, modulus} <- decode_uint(n),
         {:ok, exponent} <- decode_uint(e),
         true <- :public_key.verify(signing_input, :sha256, signature, {:RSAPublicKey, modulus, exponent}) do
      :ok
    else
      false -> {:error, :invalid_signature}
      {:error, reason} -> {:error, reason}
    end
  end

  defp verify_signature(_jwk, _signing_input, _signature), do: {:error, :unsupported_jwk}

  defp decode_uint(value) when is_binary(value) do
    case Base.url_decode64(value, padding: false) do
      {:ok, binary} -> {:ok, :binary.decode_unsigned(binary)}
      :error -> {:error, :invalid_jwk_integer}
    end
  end

  defp validate_claims(claims, opts) do
    now = Keyword.get(opts, :now, System.system_time(:second))

    with :ok <- require_claim(claims, "sub"),
         :ok <- validate_issuer(claims, Keyword.fetch!(opts, :issuer)),
         :ok <- validate_audience(claims, Keyword.fetch!(opts, :audience)),
         :ok <- validate_nonce(claims, Keyword.fetch!(opts, :nonce)),
         :ok <- validate_expiration(claims, now),
         :ok <- validate_not_before(claims, now) do
      :ok
    end
  end

  defp require_claim(claims, name) do
    if is_binary(claims[name]) and claims[name] != "", do: :ok, else: {:error, {:missing_claim, name}}
  end

  defp validate_issuer(%{"iss" => issuer}, issuer), do: :ok
  defp validate_issuer(_claims, _issuer), do: {:error, :invalid_issuer}

  defp validate_audience(%{"aud" => audience}, wanted) when is_binary(audience) do
    if audience == wanted, do: :ok, else: {:error, :invalid_audience}
  end

  defp validate_audience(%{"aud" => audiences}, wanted) when is_list(audiences) do
    if wanted in audiences, do: :ok, else: {:error, :invalid_audience}
  end

  defp validate_audience(_claims, _wanted), do: {:error, :invalid_audience}

  defp validate_nonce(%{"nonce" => nonce}, nonce), do: :ok
  defp validate_nonce(_claims, _nonce), do: {:error, :invalid_nonce}

  defp validate_expiration(%{"exp" => exp}, now) when is_integer(exp) do
    if exp + @skew_seconds >= now, do: :ok, else: {:error, :token_expired}
  end

  defp validate_expiration(_claims, _now), do: {:error, :missing_exp}

  defp validate_not_before(%{"nbf" => nbf}, now) when is_integer(nbf) do
    if nbf <= now + @skew_seconds, do: :ok, else: {:error, :token_not_yet_valid}
  end

  defp validate_not_before(_claims, _now), do: :ok
end
