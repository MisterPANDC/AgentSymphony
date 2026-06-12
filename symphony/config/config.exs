import Config

config :phoenix, :json_library, Jason

config :symphony_elixir, ecto_repos: [SymphonyElixir.Repo]

database_url = System.get_env("SYMPHONY_DATABASE_URL") || System.get_env("DATABASE_URL")

config :symphony_elixir, SymphonyElixir.Repo,
  url: database_url,
  database: System.get_env("SYMPHONY_DATABASE") || "symphony_dev",
  username: System.get_env("SYMPHONY_DATABASE_USER") || System.get_env("USER"),
  password: System.get_env("SYMPHONY_DATABASE_PASSWORD") || "",
  hostname: System.get_env("SYMPHONY_DATABASE_HOST") || "localhost",
  port: String.to_integer(System.get_env("SYMPHONY_DATABASE_PORT") || "5432"),
  pool_size: String.to_integer(System.get_env("SYMPHONY_DATABASE_POOL_SIZE") || "10")

config :symphony_elixir, SymphonyElixirWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: SymphonyElixirWeb.ErrorHTML, json: SymphonyElixirWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: SymphonyElixir.PubSub,
  secret_key_base: String.duplicate("s", 64),
  check_origin: false,
  server: false

if config_env() == :test do
  config :symphony_elixir,
    store_path:
      Path.join(
        System.tmp_dir!(),
        "symphony-test-#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive])}.json"
      )
end
