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

# The one seam to the models. Only the fake is on the other side of it until the
# live Assayer arrives; `fake` is what makes a verdict slow or absent in a test.
config :meaning_game, :keeper,
  adapter: MeaningGame.Keeper.Fake,
  fake: [delay_ms: 0, mode: :grade]

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
