defmodule SymphonyElixir.Auth.JWTTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Auth.JWT

  test "verifies RS256 token and validates OIDC claims" do
    {private_key, jwk} = rsa_keypair()

    token =
      sign(private_key, %{"alg" => "RS256", "kid" => "test-key"}, %{
        "iss" => "https://gitlab.example.com",
        "aud" => "client-id",
        "sub" => "42",
        "nonce" => "nonce-1",
        "exp" => System.system_time(:second) + 300
      })

    assert {:ok, claims} =
             JWT.verify_rs256(token, %{"keys" => [jwk]},
               issuer: "https://gitlab.example.com",
               audience: "client-id",
               nonce: "nonce-1"
             )

    assert claims["sub"] == "42"
  end

  test "rejects invalid nonce" do
    {private_key, jwk} = rsa_keypair()

    token =
      sign(private_key, %{"alg" => "RS256", "kid" => "test-key"}, %{
        "iss" => "https://gitlab.example.com",
        "aud" => "client-id",
        "sub" => "42",
        "nonce" => "nonce-1",
        "exp" => System.system_time(:second) + 300
      })

    assert {:error, :invalid_nonce} =
             JWT.verify_rs256(token, %{"keys" => [jwk]},
               issuer: "https://gitlab.example.com",
               audience: "client-id",
               nonce: "other-nonce"
             )
  end

  defp rsa_keypair do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})
    {:RSAPrivateKey, _, modulus, public_exponent, _, _, _, _, _, _, _} = private_key

    jwk = %{
      "kty" => "RSA",
      "kid" => "test-key",
      "alg" => "RS256",
      "use" => "sig",
      "n" => encode_uint(modulus),
      "e" => encode_uint(public_exponent)
    }

    {private_key, jwk}
  end

  defp sign(private_key, header, claims) do
    signing_input = encode_json(header) <> "." <> encode_json(claims)
    signature = :public_key.sign(signing_input, :sha256, private_key)
    signing_input <> "." <> Base.url_encode64(signature, padding: false)
  end

  defp encode_json(value), do: value |> Jason.encode!() |> Base.url_encode64(padding: false)
  defp encode_uint(integer), do: integer |> :binary.encode_unsigned() |> Base.url_encode64(padding: false)
end
