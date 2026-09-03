import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :meaning_game, MeaningGame.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "meaning_game_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# The server runs during test so `MeaningGameWeb.EndpointTest` can prove the
# endpoint actually boots and serves over a real socket, not just through
# `Plug.Test`. Every other test still goes through `Phoenix.ConnTest`.
config :meaning_game, MeaningGameWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  url: [host: "localhost", port: 4002],
  secret_key_base: "GGMqZggnqg1t8Q+zsg6ClM7aAnFwYXJk0/zQFqiGudcO7XNGYHZaGz9qrpv/LDYt",
  server: true

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
