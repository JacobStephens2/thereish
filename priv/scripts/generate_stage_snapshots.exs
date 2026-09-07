# priv/scripts/generate_stage_snapshots.exs
Mix.Task.run("compile")

css = File.read!("priv/static/assets/css/app.css")

out_dir = Path.expand("tmp/stage_html", File.cwd!())
File.mkdir_p!(out_dir)

defmodule StageSnapshotGenerator do
  def wrap_html(inner_html, css) do
    """
    <!DOCTYPE html>
    <html lang="en" data-theme="light">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Stage Snapshot</title>
        <style>
          #{css}
        </style>
      </head>
      <body class="bg-base-100 text-base-content antialiased">
        #{inner_html}
      </body>
    </html>
    """
  end

  def render_stage(room, assigns_override \\ %{}) do
    assigns =
      Map.merge(
        %{
          __changed__: %{},
          slug: "TEST",
          join_url: "http://localhost:4002/r/TEST",
          device_token: "tok",
          room: room
        },
        assigns_override
      )

    rendered = ThereishWeb.StageLive.render(assigns)
    Phoenix.HTML.Safe.to_iodata(rendered) |> IO.iodata_to_binary()
  end
end

base_seats_2 = [
  %{id: "s1", name: "Melissa", committed?: true},
  %{id: "s2", name: "Jacob", committed?: false}
]

base_seats_3 = [
  %{id: "s1", name: "Melissa", committed?: true},
  %{id: "s2", name: "Jacob", committed?: true},
  %{id: "s3", name: "Ada", committed?: true}
]

base_seats_6 = [
  %{id: "s1", name: "Melissa", committed?: true},
  %{id: "s2", name: "Jacob", committed?: true},
  %{id: "s3", name: "Ada", committed?: true},
  %{id: "s4", name: "Bryan", committed?: true},
  %{id: "s5", name: "Evelyn", committed?: true},
  %{id: "s6", name: "Sam", committed?: true}
]

states = [
  {"giving", %{
    phase: :giving,
    speaker?: true,
    voice: false,
    house_loop_only: false,
    seats: base_seats_2,
    gives_in: 1,
    open_seats: 0,
    seat_limit: 2,
    bookends: nil,
    attempt: %{number: 1, of: 5},
    reveal: nil,
    closed: nil,
    played: [],
    next_bookends: nil,
    overrule: nil,
    fairness_taps: %{},
    bookends_taps: %{}
  }},

  {"writing", %{
    phase: :writing,
    speaker?: true,
    voice: false,
    house_loop_only: false,
    seats: base_seats_2,
    gives_in: 2,
    open_seats: 0,
    seat_limit: 2,
    bookends: nil,
    author_step: :writing,
    attempt: %{number: 1, of: 5},
    reveal: nil,
    closed: nil,
    played: [],
    next_bookends: nil,
    overrule: nil,
    fairness_taps: %{},
    bookends_taps: %{}
  }},

  {"bridging", %{
    phase: :bridging,
    speaker?: true,
    voice: false,
    house_loop_only: false,
    seats: base_seats_2,
    gives_in: 2,
    open_seats: 0,
    seat_limit: 2,
    bookends: ["lantern", "harbour"],
    attempt: %{number: 1, of: 5},
    reveal: nil,
    closed: nil,
    played: [],
    next_bookends: nil,
    overrule: nil,
    fairness_taps: %{},
    bookends_taps: %{}
  }},

  {"assaying", %{
    phase: :assaying,
    speaker?: true,
    voice: false,
    house_loop_only: false,
    seats: base_seats_2,
    gives_in: 2,
    open_seats: 0,
    seat_limit: 2,
    bookends: ["lantern", "harbour"],
    assayer_step: :grading,
    attempt: %{number: 1, of: 5},
    reveal: nil,
    closed: nil,
    played: [],
    next_bookends: nil,
    overrule: nil,
    fairness_taps: %{},
    bookends_taps: %{}
  }},

  {"reveal_3bridges", %{
    phase: :reveal,
    speaker?: true,
    voice: false,
    house_loop_only: false,
    seats: base_seats_3,
    gives_in: 3,
    open_seats: 0,
    seat_limit: 3,
    bookends: ["lantern", "harbour"],
    attempt: %{number: 1, of: 5},
    reveal: %{
      closeness: 85,
      band: :almost,
      melded?: false,
      graded?: true,
      overruled?: false,
      bridges: [
        %{seat_id: "s1", name: "Melissa", bridge: "lighthouse"},
        %{seat_id: "s2", name: "Jacob", bridge: "pier"},
        %{seat_id: "s3", name: "Ada", bridge: "dock"}
      ],
      quip: "\"lighthouse\", \"pier\", and \"dock\" walked out to meet the water together."
    },
    closed: nil,
    played: [],
    next_bookends: ["lighthouse", "dock"],
    next_bookends_chosen?: true,
    overrule: nil,
    fairness_taps: %{},
    bookends_taps: %{}
  }},

  {"reveal_6bridges", %{
    phase: :reveal,
    speaker?: true,
    voice: false,
    house_loop_only: false,
    seats: base_seats_6,
    gives_in: 6,
    open_seats: 0,
    seat_limit: 6,
    bookends: ["mountain", "valley"],
    attempt: %{number: 2, of: 5},
    reveal: %{
      closeness: 92,
      band: :meld,
      melded?: true,
      graded?: true,
      overruled?: false,
      bridges: [
        %{seat_id: "s1", name: "Melissa", bridge: "ridge"},
        %{seat_id: "s2", name: "Jacob", bridge: "pass"},
        %{seat_id: "s3", name: "Ada", bridge: "trail"},
        %{seat_id: "s4", name: "Bryan", bridge: "cliff"},
        %{seat_id: "s5", name: "Evelyn", bridge: "canyon"},
        %{seat_id: "s6", name: "Sam", bridge: "slope"}
      ],
      quip: "Six bridges across the divide and all of them found solid footing."
    },
    closed: nil,
    played: [],
    next_bookends: nil,
    overrule: nil,
    fairness_taps: %{},
    bookends_taps: %{}
  }},

  {"closed_arc", %{
    phase: :closed,
    speaker?: true,
    voice: false,
    house_loop_only: false,
    seats: base_seats_2,
    gives_in: 2,
    open_seats: 0,
    seat_limit: 2,
    bookends: ["cairn", "beacon"],
    attempt: %{number: 5, of: 5},
    closed: %{
      because: :attempts_spent,
      attempt: 5
    },
    played: [
      %{number: 1, bookends: ["sun", "moon"], bridges: [%{name: "Melissa", bridge: "sky"}, %{name: "Jacob", bridge: "star"}], closeness: 60},
      %{number: 2, bookends: ["sky", "star"], bridges: [%{name: "Melissa", bridge: "comet"}, %{name: "Jacob", bridge: "night"}], closeness: 65},
      %{number: 3, bookends: ["comet", "night"], bridges: [%{name: "Melissa", bridge: "glow"}, %{name: "Jacob", bridge: "dark"}], closeness: 50},
      %{number: 4, bookends: ["glow", "dark"], bridges: [%{name: "Melissa", bridge: "lantern"}, %{name: "Jacob", bridge: "shadow"}], closeness: 70},
      %{number: 5, bookends: ["lantern", "shadow"], bridges: [%{name: "Melissa", bridge: "cairn"}, %{name: "Jacob", bridge: "beacon"}], closeness: 72}
    ],
    reveal: %{
      closeness: 72,
      band: :close,
      melded?: false,
      graded?: true,
      overruled?: false,
      bridges: [
        %{seat_id: "s1", name: "Melissa", bridge: "cairn"},
        %{seat_id: "s2", name: "Jacob", bridge: "beacon"}
      ],
      quip: "Five tries and you circled the fire without touching the flame."
    },
    next_bookends: nil,
    overrule: nil,
    fairness_taps: %{},
    bookends_taps: %{}
  }}
]

for {name, room} <- states do
  inner = StageSnapshotGenerator.render_stage(room)
  full = StageSnapshotGenerator.wrap_html(inner, css)
  path = Path.join(out_dir, "#{name}.html")
  File.write!(path, full)
  IO.puts("Wrote #{path} (#{byte_size(full)} bytes)")
end
