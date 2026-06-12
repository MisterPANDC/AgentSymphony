Application.put_env(
  :symphony_elixir,
  :store_path,
  Path.join(
    System.tmp_dir!(),
    "symphony-test-#{System.os_time(:nanosecond)}-#{System.unique_integer([:positive])}.json"
  )
)

unless System.get_env("SYMPHONY_STORE_BACKEND") == "postgres" and System.get_env("SYMPHONY_DATABASE_URL") do
  ExUnit.configure(exclude: [postgres: true])
end

ExUnit.start()
