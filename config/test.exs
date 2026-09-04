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

# The couch is promised 2.5 seconds; a test suite is not. Tests that are about
# the beat itself set their own with `MeaningGame.RoomFixtures.beat/1`.
config :meaning_game, reveal_beat_ms: 5

# No test grades against a provider. The suite must never spend money and never
# depend on somebody's uptime, so the fake is the Assayer here and the handful
# of tests that exercise the live adapter put a recorded response behind it.
# Everything else about the Assayer — its provider, model, effort, hedging and
# prices — is deliberately the couch's own configuration, so that the tests
# which do exercise the live adapter exercise the settings that will be live.
#
# `http_options` fences the suite off from the network entirely: every request a
# provider adapter makes goes to a recorded response instead. A test that means
# to call somebody has to say so out loud
# (`MeaningGame.KeeperFixtures.let_it_call_the_provider/0`), and is tagged
# `:live` and excluded from the default run.
config :meaning_game, :keeper,
  adapter: MeaningGame.Keeper.Fake,
  roles: [
    assayer: [timeout_ms: 1_000, deadline_ms: 2_000, api_key: "recorded-responses-need-no-key"]
  ],
  http_options: [plug: {Req.Test, MeaningGame.Keeper.Gemini}]

# The escalation ladder, in test time. The shape is what matters — activity,
# then a provisional reading, then no verdict — and the shape is the same at a
# fortieth of the wall clock.
config :meaning_game, assayer_escalation_ms: [slow: 100, provisional: 200, unavailable: 250]

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
