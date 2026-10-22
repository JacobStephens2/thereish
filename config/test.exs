import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :thereish, Thereish.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "meaning_game_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

# The server runs during test so `ThereishWeb.EndpointTest` can prove the
# endpoint actually boots and serves over a real socket, not just through
# `Plug.Test`. Every other test still goes through `Phoenix.ConnTest`.
#
# One suite per port: because it really listens, two worktrees running
# `mix test` in the same moment would collide on 4002 with `:eaddrinuse`. The
# partition that already names the database names the port too, so parallel
# tickets each get their own; with no partition it is 4002 as before.
test_port =
  case System.get_env("TEST_PORT") || System.get_env("MIX_TEST_PARTITION") do
    nil ->
      4002

    port when is_binary(port) ->
      case Integer.parse(port) do
        {p, ""} -> p
        _ -> 4010 + :erlang.phash2(port, 990)
      end
  end

# The suite does not run in the app container, so it cannot learn the bridge
# gateway from the container's default route. The forwarded-address cases use
# this hop: docker0's gateway, and not the rest of 172.17.0.0/16.
config :thereish, :bridge_gateway, {172, 17, 0, 1}

config :thereish, ThereishWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: test_port],
  url: [host: "localhost", port: test_port],
  secret_key_base: "GGMqZggnqg1t8Q+zsg6ClM7aAnFwYXJk0/zQFqiGudcO7XNGYHZaGz9qrpv/LDYt",
  server: true

# The couch is promised 2.5 seconds; a test suite is not. Tests that are about
# the beat itself set their own with `Thereish.RoomFixtures.beat/1`.
config :thereish, reveal_beat_ms: 5

# The couch is promised five seconds after a reveal; a test suite is not.
# Tests that are about the hold set their own with
# `Thereish.RoomFixtures.reveal_hold/1` and move the clock rather than sleeping.
config :thereish, reveal_hold_ms: 0

# Suppress missing-key warnings during test suite boots.
config :thereish, boot_warnings: false

# No test grades against a provider. The suite must never spend money and never
# depend on somebody's uptime, so the fake is the Assayer here and the handful
# of tests that actually call somebody (the live smoke test) are tagged
# `:live` and excluded from the default run.
config :thereish, :steward,
  adapter: Thereish.Steward.Fake,
  roles: [
    assayer: [timeout_ms: 1_000, deadline_ms: 2_000, api_key: "recorded-responses-need-no-key"],
    author: [timeout_ms: 2_000, deadline_ms: 5_000, api_key: "recorded-responses-need-no-key"],
    scribe: [
      api_key: "recorded-responses-need-no-key",
      jobs: [
        recap: [timeout_ms: 2_000, deadline_ms: 5_000],
        naming: [timeout_ms: 500, deadline_ms: 1_000],
        title: [timeout_ms: 500, deadline_ms: 1_000]
      ]
    ],
    foley: [
      levels: [music: 0.5, stings: 1.2, voice: 1.2, duck: 0.15, duck_stings: 0.35],
      meld_cue_delay_ms: 1800,
      eleven_labs_api_key: "recorded-responses-need-no-key",
      hume_api_key: "recorded-responses-need-no-key",
      hume_secret_key: "recorded-responses-need-no-key",
      jobs: [
        effects: [timeout_ms: 1_000, api_key: "recorded-responses-need-no-key"],
        vamp: [timeout_ms: 1_000, api_key: "recorded-responses-need-no-key"],
        music: [
          deadline_ms: 2_000,
          poll_interval_ms: 5,
          timeout_ms: 1_000,
          api_key: "recorded-responses-need-no-key"
        ],
        ear: [timeout_ms: 1_000, api_key: "recorded-responses-need-no-key"],
        voice: [
          provider: Thereish.Steward.Hume,
          voice_id: "44cb3a51-07b4-4934-83fd-9d9e8d363ce6",
          timeout_ms: 3_000
        ]
      ]
    ],
    limner: [
      provider: Thereish.Steward.Fal,
      model: "fal-ai/flux/schnell",
      size: 64,
      seed: 84,
      timeout_ms: 1_000,
      deadline_ms: 2_000,
      poll_interval_ms: 5,
      api_key: "recorded-responses-need-no-key",
      references: []
    ]
  ],
  http_options: [plug: {Req.Test, Thereish.Steward.Gemini}]

# The escalation ladder, in test time. The shape is what matters — activity,
# then no verdict — and the shape is the same at a fortieth of the wall clock.
config :thereish, assayer_escalation_ms: [slow: 100, unavailable: 250]
config :thereish, author_escalation_ms: [still_writing: 100, deadline: 250]

# Print only warnings and errors during test
config :logger, level: :warning

# Bcrypt's real cost is for production; tests only need the hash to round-trip.
config :bcrypt_elixir, log_rounds: 1

# Disable swoosh api client as it is not needed for tests
config :swoosh, :api_client, false

config :thereish, Thereish.Mailer, adapter: Swoosh.Adapters.Test

config :thereish, :notice,
  to: "operator@example.com",
  from: "notice@thereish.app"

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
