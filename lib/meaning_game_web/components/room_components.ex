defmodule MeaningGameWeb.RoomComponents do
  @moduledoc """
  The parts of a Room that both the phones and the stage draw.

  Each of these is one component on purpose: "the stage lists who has joined;
  phones show the same roster" is a rule, and a rule with two implementations is
  a rule with two answers. The same goes for the Anchors and, most of all, for
  the reveal — the number the stage shouts and the number the phone shows have
  to be the same number.

  Everything here reads a snapshot and nothing here decides anything. What a
  Seat may see was settled by `MeaningGame.Game.view/2` before it got here.
  """
  use MeaningGameWeb, :html

  attr :room, :map, required: true, doc: "a snapshot from MeaningGame.Rooms.snapshot/2"

  def roster(assigns) do
    ~H"""
    <div data-role="roster">
      <ul class="flex flex-col gap-2">
        <li
          :for={seat <- @room.seats}
          data-seat={seat.id}
          data-committed={to_string(seat.committed?)}
          class="flex items-center gap-2 text-lg"
        >
          <span class="size-2 rounded-full bg-primary" aria-hidden="true"></span>
          <span>{seat.name}</span>
          <span :if={seat.you?} class="text-sm opacity-60">(you)</span>
          <span :if={seat.committed? and mid_page?(@room)} class="text-sm opacity-60">
            has written a bridge
          </span>
        </li>
        <li :if={@room.seats == []} class="text-lg opacity-60">Nobody yet</li>
      </ul>

      <p data-role="open-seats" class="mt-3 text-sm opacity-60">{waiting(@room)}</p>
    </div>
    """
  end

  attr :room, :map, required: true

  @doc "The two words the Page hangs between, shown to everyone at once."
  def anchors(assigns) do
    ~H"""
    <div
      :if={@room.anchors}
      data-role="anchors"
      class="flex flex-wrap items-center justify-center gap-4"
    >
      <span
        :for={anchor <- @room.anchors}
        class="rounded-lg bg-base-200 px-5 py-3 text-3xl font-semibold tracking-tight"
      >
        {anchor}
      </span>
    </div>
    """
  end

  attr :room, :map, required: true

  @doc """
  Which try this is, and how many the Page gets.

  Shown while a Page is being played and not once it has ended, because at the
  end the number that matters is which attempt it landed on rather than how many
  are left.
  """
  def attempt(assigns) do
    ~H"""
    <p
      :if={@room.phase in [:bridging, :assaying, :reveal]}
      data-role="attempt"
      class="text-center text-sm uppercase tracking-widest opacity-60"
    >
      Attempt {@room.attempt.number} of {@room.attempt.of}
    </p>
    """
  end

  attr :room, :map, required: true

  @doc """
  The beat, said out loud. Every screen says the same thing during it.

  And if the Assayer is slow, every screen says so together: activity through
  four seconds, a provisional reading at eight, and at ten the game says it has
  no verdict, which is not a line here because by then there is a reveal to draw
  (design law 10). A wait the game narrates is a wait; a wait it says nothing
  about is a hang.
  """
  def assaying(assigns) do
    ~H"""
    <p
      :if={@room.phase == :assaying}
      data-role="phase"
      data-step={@room.assayer_step || :grading}
      class="text-center text-lg opacity-70"
    >
      {waiting_line(@room.assayer_step)}
    </p>
    """
  end

  attr :room, :map, required: true

  @doc """
  The reveal: the Bridges side by side, then the number, then the joke, then the
  argument.

  In that order deliberately — the comparison is meant to land before the grade
  does. The number is the joke's delivery, so it is the biggest thing on the
  screen; the quip lands on top of it, naming the two words they actually wrote
  (ADR-0005); and the Assayer's reasoning is under both because the players are
  supposed to be able to argue with it.
  """
  def reveal(assigns) do
    ~H"""
    <section :if={@room.reveal} data-role="reveal" class="flex flex-col items-center gap-6">
      <div class="flex flex-wrap items-stretch justify-center gap-4">
        <div
          :for={bridge <- @room.reveal.bridges}
          data-bridge={bridge.seat_id}
          class="flex min-w-40 flex-col gap-1 rounded-lg border border-base-300 px-5 py-3 text-center"
        >
          <span class="text-sm uppercase tracking-wide opacity-60">{bridge.name}</span>
          <span class="text-2xl font-semibold">{bridge.bridge}</span>
        </div>
      </div>

      <div :if={@room.reveal.closeness} class="flex flex-col items-center">
        <span data-role="closeness" class="text-7xl font-bold leading-none">
          {@room.reveal.closeness}
        </span>
        <span data-role="band" class="mt-1 text-xl uppercase tracking-widest">
          {band(@room.reveal.band)}
        </span>
        <span :if={@room.reveal.melded?} class="mt-1 text-sm opacity-70">One mind, two heads.</span>
      </div>

      <p :if={@room.reveal.closeness == nil} data-role="no-verdict" class="text-xl">
        No verdict. This one is yours to call.
      </p>

      <ul class="flex max-w-prose flex-col gap-5 text-center">
        <li
          :for={pair <- @room.reveal.pairs}
          data-role="pair"
          data-melded={to_string(pair.melded?)}
          class="flex flex-col gap-1"
        >
          <p :if={length(@room.reveal.pairs) > 1} class="font-semibold">
            {Enum.join(pair.names, " + ")} — {pair.closeness || "no verdict"} {band(pair.band)}
            <span :if={pair.melded?} data-role="pair-meld">· melded</span>
          </p>
          <p :if={pair.quip} data-role="quip" class="text-xl">{pair.quip}</p>
          <p data-role="reasoning" class="opacity-80">
            {pair.reasoning || "The Assayer could not say."}
          </p>
        </li>
      </ul>
    </section>
    """
  end

  attr :room, :map, required: true

  @doc """
  What a miss means, said out loud on every screen: the Bridges that missed are
  the next attempt's Anchors.

  One component rather than a line on each view, because "a miss converges" is a
  rule, and a rule said in two wordings is two rules.
  """
  def carry_forward(assigns) do
    ~H"""
    <p
      :if={@room.phase == :reveal}
      data-role="carry-forward"
      class="text-center text-sm opacity-70"
    >
      Those two words become the next anchors.
    </p>
    """
  end

  attr :room, :map, required: true

  @doc """
  The end of a Page, said as an ending.

  A Page that ran out of attempts has not gone wrong, and this line is the whole
  difference between an ending and an error message: the players spent five
  tries on two words and did not converge, which is the game working.
  """
  def ending(assigns) do
    ~H"""
    <section :if={@room.closed} data-role="ending" class="flex flex-col items-center gap-4">
      <p data-role="ending-line" class="max-w-prose text-center text-xl">
        {ending_line(@room.closed)}
      </p>

      <ol :if={@room.played != []} data-role="arc" class="flex flex-col gap-1 text-sm opacity-70">
        <li
          :for={attempt <- @room.played}
          data-attempt={attempt.number}
          class="flex flex-wrap items-baseline justify-center gap-2"
        >
          <span>{Enum.join(attempt.anchors, " + ")}</span>
          <span aria-hidden="true">→</span>
          <span class="font-semibold">
            {attempt.bridges |> Enum.map(& &1.bridge) |> Enum.join(" · ")}
          </span>
          <span>{attempt.closeness || "no verdict"}</span>
        </li>
      </ol>
    </section>
    """
  end

  # The Page landed it. Which attempt it took is the story, so it is the thing
  # the line names.
  defp ending_line(%{because: :meld, attempt: 1}), do: "That's the Page — melded first try."

  defp ending_line(%{because: :meld, attempt: attempt}),
    do: "That's the Page — melded on attempt #{attempt}."

  defp ending_line(%{because: :attempts_spent, attempt: attempt}),
    do: "That's the Page — #{attempt} attempts, and the words kept their distance."

  @doc """
  Whether the Room is still between the Anchors and the reveal.

  Once the Bridges are up on the screen, who had already written one and what
  this phone wrote are answered by the reveal itself, and saying it twice makes
  the reveal read as a page still in progress.
  """
  def mid_page?(room), do: room.phase in [:bridging, :assaying]

  # The rules name a rung; nobody says "deep_meld" out loud.
  defp band(nil), do: ""
  defp band(name), do: name |> to_string() |> String.replace("_", " ")

  # The Assayer has answered and the beat is still running, which is the
  # ordinary case and reads as the ordinary line.
  defp waiting_line(nil), do: "Every bridge is in. The Assayer is looking at them."
  defp waiting_line(:grading), do: waiting_line(nil)
  defp waiting_line(:slow), do: "The Assayer is still reading. It does this sometimes."

  # Where the Author's pre-graded table will put a provisional band once there
  # is an Author to write one. Until then the honest thing is to keep saying
  # what is happening rather than to guess at a number.
  defp waiting_line(:provisional), do: "Still nothing. Hold on."

  defp waiting(%{open_seats: 0, seat_limit: seat_limit}),
    do: "All #{seat_limit} seats taken"

  defp waiting(%{open_seats: 1}), do: "Waiting for 1 more"
  defp waiting(%{open_seats: open}), do: "Waiting for #{open} more"
end
