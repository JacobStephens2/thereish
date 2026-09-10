# priv/scripts/generate_mobile_snapshot.exs
Mix.Task.run("compile")

css = File.read!("priv/static/assets/css/app.css")

out_dir = Path.expand("tmp/mobile_html", File.cwd!())
File.mkdir_p!(out_dir)

defmodule MobileSnapshotGenerator do
  def wrap_html(inner_html, css) do
    """
    <!DOCTYPE html>
    <html lang="en" data-theme="dark" class="bg-base-100">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Mobile Phone Snapshot</title>
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

  def render_room(room, assigns_override \\ %{}) do
    assigns =
      Map.merge(
        %{
          __changed__: %{},
          slug: "daws",
          code: "daws",
          join_url: "https://thereish.app/r/daws",
          stage_present?: false,
          seat: %{id: "s2", name: "Jacob"},
          name: "Jacob",
          error: nil,
          page_error: nil,
          room: room
        },
        assigns_override
      )

    rendered = ThereishWeb.RoomLive.render(assigns)
    Phoenix.HTML.Safe.to_iodata(rendered) |> IO.iodata_to_binary()
  end
end

base_room = %{
  seat_limit: 2,
  speaker?: false,
  speaker_claimed?: false,
  voice: false,
  music: "page",
  quip: nil,
  seats: [],
  you: nil,
  verdict: nil,
  bookends: nil,
  bridges: [],
  next_bookends: nil,
  next?: false,
  never?: false,
  playing: nil,
  track: nil,
  loop: nil,
  gives_in: 0,
  your_give: nil,
  your_bridge: nil,
  author_failure: nil,
  late?: false,
  reveal: nil,
  closed: nil,
  open_seats: 2,
  overrule: nil,
  played: [],
  bookends_taps: %{},
  fairness_taps: %{}
}

room_closed =
  Map.merge(base_room, %{
    phase: :closed,
    speaker_claimed?: true,
    open_seats: 0,
    gives_in: 2,
    your_give: "savanna",
    your_bridge: "simba",
    seats: [
      %{id: "s1", name: "Wifey", committed?: true, partner_id: nil, you?: false},
      %{id: "s2", name: "Jacob", committed?: true, partner_id: nil, you?: true}
    ],
    you: %{id: "s2", name: "Jacob", partner_name: nil},
    closed: %{
      because: :meld,
      attempt: 1
    },
    played: [
      %{
        number: 1,
        bookends: ["mufasa", "slide into the craggy cliffs"],
        bridges: [%{bridge: "murder"}, %{bridge: "simba"}],
        closeness: 74
      }
    ]
  })

room_waiting = Map.merge(base_room, %{phase: :waiting})

html_closed = MobileSnapshotGenerator.render_room(room_closed)
File.write!(Path.join(out_dir, "closed_phone.html"), MobileSnapshotGenerator.wrap_html(html_closed, css))

html_waiting = MobileSnapshotGenerator.render_room(room_waiting, %{seat: nil})
File.write!(Path.join(out_dir, "waiting_phone.html"), MobileSnapshotGenerator.wrap_html(html_waiting, css))

IO.puts("Wrote tmp/mobile_html/closed_phone.html and waiting_phone.html")
