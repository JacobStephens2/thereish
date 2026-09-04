# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :meaning_game,
  ecto_repos: [MeaningGame.Repo],
  # Microseconds, because insertion order is display order: the roster, the
  # reveal, and every Chronicle table to come are read in the order the rows
  # were written, and a second is wide enough for two players to tie in.
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true],
  # How many Seats a new Room holds. Two is a setting, not an assumption: no
  # rule anywhere is written for a pair rather than for a list (ADR-0007).
  seats_per_room: 2,
  # The Room the bare URL opens, so the couch needs no path to remember.
  default_room_slug: "couch",
  # The reveal is a fixed beat, not a wait (design law 10). One number for every
  # grade in v1: whether a harsh grade should be revealed sooner is a question
  # the couch answers, not one to guess at here.
  reveal_beat_ms: 2500,
  # How the reveal escalates when the Assayer is slow (design law 10). Visible
  # activity through four seconds; a provisional reading at eight, which shows
  # the waiting state until the Author exists to pre-grade one; and at ten the
  # game states it has no verdict and hands the ruling to the players. Ten
  # seconds is a ceiling, not a target: the measured p95 is around one.
  assayer_escalation_ms: [slow: 4_000, provisional: 8_000, unavailable: 10_000],
  # How many tries a Page gets before it closes unmelded. Five is a guess about
  # how long a converging arc stays funny, which makes it a setting the couch
  # moves rather than a number in the rules.
  attempts_per_page: 5,
  # The ladder a closeness is read on. All of it is configuration because all of
  # it is calibration — the boundaries move as the couple's fairness taps say
  # they should, and a Meld starts at the floor of the `meld` band.
  ladder: [
    scale: 0..100,
    bands: [miss: 0, adjacent: 30, near: 55, meld: 75, deep_meld: 90]
  ]

# The one seam to the models. Two adapters satisfy it: the live one, which is
# what the couch plays against, and the fake, which is what every test that is
# not a hand-run smoke test grades against (`fake` is what makes a verdict slow
# or absent in a test).
#
# Everything about a role is here rather than in the code, so that swapping the
# Assayer is a setting and not a refactor: the model, the effort, how many
# identical requests are hedged, and how long the Steward waits before it says it
# has nothing. The Assayer is Gemini 3.8 Flash at low effort per ADR-0005 —
# chosen for repeatability, because a constant offset is calibrated once by the
# couple while noise makes the first grade on a borderline pair a dice roll that
# the cache then freezes as precedent.
config :meaning_game, :steward,
  adapter: MeaningGame.Steward.Live,
  fake: [delay_ms: 0, mode: :grade],
  roles: [
    assayer: [
      provider: MeaningGame.Steward.Gemini,
      model: "gemini-3.8-flash",
      # Thinking cannot be turned off on 3.8 Flash; low is the floor.
      effort: "low",
      max_tokens: 400,
      # Two identical requests to one model, first answer wins. Fast tier only:
      # hedging shortens a tail made of queueing, and does nothing for a tail
      # made of generation (design law 11).
      requests: 2,
      # A rejected answer is asked for again, twice, before the Steward gives up.
      retries: 2,
      # How long one request may take. The measured p95 for a whole verdict is
      # around a second, so four is a request that has gone wrong — and it is
      # short enough that a rejected answer can be asked for again inside the
      # budget below, which is what makes the retries real (design law 14).
      timeout_ms: 4_000,
      # The whole grading's budget, retries and all. Under the ten seconds at
      # which the reveal stops waiting, so that the Steward has already said it
      # has nothing by the time the game does.
      deadline_ms: 9_000,
      # Filled in from GEMINI_API_KEY by `config/runtime.exs`. A key is a
      # setting like the model is; nothing reaches for the environment mid-Page.
      api_key: nil
    ],
    author: [
      provider: MeaningGame.Steward.Anthropic,
      model: "claude-fable-5-1",
      effort: "low",
      max_tokens: 100_000,
      retries: 2,
      timeout_ms: 120_000,
      deadline_ms: 300_000,
      api_key: nil
    ]
  ],
  # Dollars per million tokens, {input, output}, from each provider's pricing
  # page on 2026-09-02. Google's promotional rate for Flash runs to 2026-12-31;
  # $1.50 / $7.50 after that. Fable 5.1 is $10 / $50.
  prices: %{
    "gemini-3.8-flash" => {0.75, 3.75},
    "claude-fable-5-1" => {10.0, 50.0}
  },
  # The most Seats a Room may hold, because live grading is N choose 2 requests
  # per attempt and six Seats is already fifteen of them. A limit on what a
  # reveal can afford, not on what the rules can say.
  seat_cap: 6

# Configure the endpoint
config :meaning_game, MeaningGameWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MeaningGameWeb.ErrorHTML, json: MeaningGameWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MeaningGame.PubSub,
  live_view: [signing_salt: "2WJS9hIh"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  meaning_game: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  meaning_game: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
