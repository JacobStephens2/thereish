# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :meaning_game,
  env: config_env(),
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
  # activity through four seconds; at ten the game states it has no verdict and
  # hands the ruling to the players. Ten seconds is a ceiling, not a target: the
  # measured p95 is around one.
  assayer_escalation_ms: [slow: 4_000, unavailable: 10_000],
  # How the wait escalates when the Author is slow (spec: The Author fails honestly).
  # At five seconds every screen says the Author is still writing; at the eight-second
  # deadline the Room fails with a timeout reason and offers Try again and New settings.
  author_escalation_ms: [still_writing: 5_000, deadline: 8_000],
  # How many tries a Page gets before it closes unmelded. Five is a guess about
  # how long a converging arc stays funny, which makes it a setting the couch
  # moves rather than a number in the rules.
  attempts_per_page: 5,
  # The ladder a closeness is read on. All of it is configuration because all of
  # it is calibration — the boundaries move as the couple's fairness taps say
  # they should, and a Meld starts at the floor of the `meld` band.
  ladder: [
    scale: 0..100,
    bands: [miss: 0, adjacent: 30, close: 55, almost: 75, meld: 90, deep_meld: 100]
  ],
  # First-party cookieless analytics via Umami (ticket 11)
  umami: [
    script_url: nil,
    website_id: nil
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
      # A quip request on a Precedent hit runs inside the beat (2,500 ms), so
      # its timeout is shorter than the full grading timeout.
      quip_timeout_ms: 2_000,
      # The whole grading's budget, retries and all. Under the ten seconds at
      # which the reveal stops waiting, so that the Steward has already said it
      # has nothing by the time the game does.
      deadline_ms: 9_000,
      # Filled in from GEMINI_API_KEY by `config/runtime.exs`. A key is a
      # setting like the model is; nothing reaches for the environment mid-Page.
      api_key: nil
    ],
    author: [
      provider: MeaningGame.Steward.Gemini,
      model: "gemini-3.8-flash",
      effort: "low",
      max_tokens: 400,
      requests: 1,
      retries: 1,
      timeout_ms: 8_000,
      deadline_ms: 8_000,
      api_key: nil,
      jobs: [
        flash: [
          provider: MeaningGame.Steward.Gemini,
          model: "gemini-3.8-flash",
          effort: "low",
          max_tokens: 400,
          timeout_ms: 8_000,
          deadline_ms: 8_000
        ],
        astra: [
          provider: MeaningGame.Steward.OpenAI,
          model: "gpt-6-astra",
          effort: "low",
          max_tokens: 400,
          timeout_ms: 8_000,
          deadline_ms: 8_000
        ]
      ]
    ],
    # The Scribe is the one role whose jobs want different models, so it is the
    # one role configured per job. Naming a Room happens with a table waiting
    # for a Code and wants the fast tier; writing a recap happens after everyone
    # has gone to bed and wants the model that writes well. A `jobs` entry
    # inherits everything the role says and overrides what it names.
    scribe: [
      api_key: nil,
      # One repair pass and no more (design law 14). The gates hand back the
      # rule that fired, a model told which rule fired usually fixes it, and a
      # model that did not fix it the first time writes a worse paragraph the
      # third — there is no player waiting, so a missing recap costs nothing.
      retries: 1,
      jobs: [
        recap: [
          # `claude-fable-5-1` because the Steward prototype measured it writing
          # the best recaps of the models benched, and long ones — which is what
          # the Vale gate is for rather than a reason to pick a worse writer.
          #
          # Effort is low because the role furthest from the table is not nine
          # dollars in ten: the ten recaps to date were $0.71 of the $0.80 ever
          # spent (spec, "Spend and the record").
          # xhigh is kept as a one-line alternative if prose quality requires it:
          # effort: "xhigh",
          provider: MeaningGame.Steward.Anthropic,
          model: "claude-fable-5-1",
          effort: "low",
          max_tokens: 8_000,
          # Nobody is waiting. The budget is generous because a recap that takes
          # a minute is a recap, and a recap that was rushed is a paragraph the
          # couple will read next month.
          timeout_ms: 60_000,
          deadline_ms: 150_000
        ],
        naming: [
          # Gemini 3.8 Flash at low effort, because a table is waiting (spec,
          # "The Scribe's first job"). One request, no hedging, a short timeout
          # and a deadline shorter than the Assayer's.
          provider: MeaningGame.Steward.Gemini,
          model: "gemini-3.8-flash",
          effort: "low",
          max_tokens: 400,
          requests: 1,
          timeout_ms: 2_500,
          deadline_ms: 5_000
        ],
        title: [
          # Gemini 3.8 Flash at low effort, a one-field schema, a short timeout
          # and deadline in the naming job's class (spec: The Scribe titles the Track).
          provider: MeaningGame.Steward.Gemini,
          model: "gemini-3.8-flash",
          effort: "low",
          max_tokens: 200,
          requests: 1,
          timeout_ms: 2_500,
          deadline_ms: 5_000
        ]
      ]
    ],
    foley: [
      levels: [music: 0.5, stings: 1.2, voice: 1.2, duck: 0.15],
      meld_cue_delay_ms: 1800,
      elevenlabs_api_key: nil,
      hume_api_key: nil,
      hume_secret_key: nil,
      jobs: [
        effects: [
          provider: MeaningGame.Steward.ElevenLabs,
          model: "eleven_text_to_sound_v2",
          format: "mp3_44100_128",
          timeout_ms: 30_000,
          api_key: nil
        ],
        music: [
          provider: MeaningGame.Steward.Mureka,
          model: "auto",
          n: 1,
          deadline_ms: 180_000,
          poll_interval_ms: 2_000,
          timeout_ms: 30_000,
          api_key: nil
        ],
        ear: [
          provider: MeaningGame.Steward.Gemini,
          model: "gemini-3.8-flash",
          effort: "low",
          max_tokens: 1_000,
          timeout_ms: 90_000,
          api_key: nil
        ],
        # Either provider is one config line. Dungeon Master (Hume, bake-off winner) with George (ElevenLabs) as alternative.
        voice: [
          provider: MeaningGame.Steward.Hume,
          voice_id: "44cb3a51-07b4-4934-83fd-9d9e8d363ce6",
          timeout_ms: 3_000
        ]
        # Alternative:
        # voice: [provider: MeaningGame.Steward.ElevenLabs, voice_id: "JBFqnCBsd6RMkjVDRZzb", timeout_ms: 3_000]
      ]
    ]
  ],
  # Dollars per million tokens, {input, output}, from each provider's pricing
  # page on 2026-09-02, and per-character rates for voice models from
  # 2026-09-05 ($0.10/1k chars for ElevenLabs v3 Conversational, $0.15/1k chars
  # for Hume Octave 2).
  prices: %{
    "gemini-3.8-flash" => {0.75, 3.75},
    "gpt-6-astra" => {1.0, 4.0},
    "claude-fable-5-1" => {10.0, 50.0},
    # ElevenLabs sound generation ($0.10 / 1k characters)
    "eleven_text_to_sound_v2" => 0.00010,
    # Mureka instrumental music ($0.04 / track; Mureka's model identifier is "auto")
    "auto" => {:track, 0.04},
    "eleven_v3_conversational" => 0.00010,
    "octave-2" => 0.00015
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

# Room creation rate limiting: sliding hour in memory per device and per address
config :meaning_game, :room_creation_rate_limit,
  per_device: 10,
  per_address: 30,
  window_seconds: 3600

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Configure Swoosh API client
config :swoosh, :api_client, Swoosh.ApiClient.Req

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
