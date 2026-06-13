defmodule SymphonyElixir.Auth.Config do
  @moduledoc """
  Runtime authentication configuration.

  Local development keeps the current single-user behaviour. Cloud deployments
  opt in to GitLab OIDC with `SYMPHONY_AUTH_MODE=gitlab_oidc`.
  """

  alias Symphony.GitLab
  alias SymphonyElixir.Dotenv

  defstruct [
    :mode,
    :issuer,
    :client_id,
    :client_secret,
    :redirect_uri,
    :public_url,
    scopes: ~w(openid profile email api),
    min_access_level: 20,
    write_access_level: 30,
    admin_access_level: 40
  ]

  @type t :: %__MODULE__{
          mode: String.t(),
          issuer: String.t() | nil,
          client_id: String.t() | nil,
          client_secret: String.t() | nil,
          redirect_uri: String.t() | nil,
          public_url: String.t() | nil,
          scopes: [String.t()],
          min_access_level: non_neg_integer(),
          write_access_level: non_neg_integer(),
          admin_access_level: non_neg_integer()
        }

  @spec load(keyword()) :: {:ok, t()} | {:error, term()}
  def load(opts \\ []) do
    if Keyword.get(opts, :load_env_file, true), do: Dotenv.load()

    mode = System.get_env("SYMPHONY_AUTH_MODE") || "local_single_user"

    config = %__MODULE__{
      mode: mode,
      issuer: oidc_issuer(),
      client_id: blank_to_nil(System.get_env("GITLAB_OIDC_CLIENT_ID")),
      client_secret: blank_to_nil(System.get_env("GITLAB_OIDC_CLIENT_SECRET")),
      public_url: public_url(),
      scopes: scopes(),
      min_access_level: int_env("SYMPHONY_AUTH_MIN_ACCESS_LEVEL", 20),
      write_access_level: int_env("SYMPHONY_AUTH_WRITE_ACCESS_LEVEL", 30),
      admin_access_level: int_env("SYMPHONY_AUTH_ADMIN_ACCESS_LEVEL", 40)
    }

    config = %{config | redirect_uri: redirect_uri(config)}

    if oidc_enabled?(config), do: validate_oidc(config), else: {:ok, config}
  end

  @spec oidc_enabled?(t()) :: boolean()
  def oidc_enabled?(%__MODULE__{mode: "gitlab_oidc"}), do: true
  def oidc_enabled?(_config), do: false

  @spec local_user() :: map()
  def local_user do
    %{
      id: "local",
      provider: "local",
      username: "local_operator",
      name: "Local Operator",
      email: nil,
      avatar_url: nil,
      profile_url: nil,
      access_level: 50,
      role: "Owner",
      local?: true
    }
  end

  @spec role_for_access_level(integer() | nil) :: String.t()
  def role_for_access_level(level) when is_integer(level) do
    cond do
      level >= 50 -> "Owner"
      level >= 40 -> "Maintainer"
      level >= 30 -> "Developer"
      level >= 20 -> "Reporter"
      level >= 10 -> "Guest"
      level >= 5 -> "Minimal"
      true -> "No access"
    end
  end

  def role_for_access_level(_level), do: "No access"

  defp validate_oidc(%__MODULE__{} = config) do
    missing =
      [
        {:GITLAB_OIDC_ISSUER, config.issuer},
        {:GITLAB_OIDC_CLIENT_ID, config.client_id},
        {:GITLAB_OIDC_CLIENT_SECRET, config.client_secret},
        {:SYMPHONY_PUBLIC_URL, config.public_url}
      ]
      |> Enum.filter(fn {_name, value} -> is_nil(value) end)
      |> Enum.map_join(", ", fn {name, _value} -> Atom.to_string(name) end)

    if missing == "" do
      {:ok, config}
    else
      {:error, {:missing_oidc_config, missing}}
    end
  end

  defp oidc_issuer do
    blank_to_nil(System.get_env("GITLAB_OIDC_ISSUER")) ||
      blank_to_nil(System.get_env("GITLAB_BASE_URL")) ||
      gitlab_base_url_from_project_api_url()
  end

  defp gitlab_base_url_from_project_api_url do
    with url when is_binary(url) <- blank_to_nil(System.get_env("GITLAB_PROJECT_API_URL")),
         {:ok, config} <- GitLab.Config.parse_project_api_url(url) do
      config.gitlab_base_url
    else
      _ -> nil
    end
  end

  defp public_url do
    System.get_env("SYMPHONY_PUBLIC_URL")
    |> blank_to_nil()
    |> case do
      nil -> nil
      url -> String.trim_trailing(url, "/")
    end
  end

  defp redirect_uri(%__MODULE__{public_url: nil}), do: nil
  defp redirect_uri(%__MODULE__{public_url: public_url}), do: public_url <> "/auth/gitlab/callback"

  defp scopes do
    case blank_to_nil(System.get_env("GITLAB_OIDC_SCOPES")) do
      nil -> ~w(openid profile email api)
      raw -> raw |> String.split(~r/[\s,]+/, trim: true) |> Enum.uniq()
    end
  end

  defp int_env(name, default) do
    case System.get_env(name) do
      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} when int >= 0 -> int
          _ -> default
        end

      _ ->
        default
    end
  end

  defp blank_to_nil(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp blank_to_nil(_value), do: nil
end
