postgres_url? = not is_nil(System.get_env("SYMPHONY_DATABASE_URL") || System.get_env("DATABASE_URL"))
postgres_tests? = System.get_env("SYMPHONY_STORE_BACKEND") == "postgres" and postgres_url?

unless postgres_tests? do
  ExUnit.configure(exclude: [postgres: true])
end

ExUnit.start()
