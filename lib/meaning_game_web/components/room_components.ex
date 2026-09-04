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
          <span :if={seat.committed? and @room.phase != :reveal} class="text-sm opacity-60">
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

  @doc "The beat, said out loud. Every screen says the same thing during it."
  def assaying(assigns) do
    ~H"""
    <p
      :if={@room.phase == :assaying}
      data-role="phase"
      class="text-center text-lg opacity-70"
    >
      Every bridge is in. The Assayer is looking at them.
    </p>
    """
  end

  attr :room, :map, required: true

  @doc """
  The reveal: the Bridges side by side, then the number, then the argument.

  In that order deliberately — the comparison is meant to land before the grade
  does. The number is the joke's delivery, so it is the biggest thing on the
  screen, and the Assayer's reasoning is under it because the players are
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

      <ul class="flex max-w-prose flex-col gap-3 text-center">
        <li :for={pair <- @room.reveal.pairs} data-role="pair" data-melded={to_string(pair.melded?)}>
          <p :if={length(@room.reveal.pairs) > 1} class="font-semibold">
            {Enum.join(pair.names, " + ")} — {pair.closeness || "no verdict"} {band(pair.band)}
            <span :if={pair.melded?} data-role="pair-meld">· melded</span>
          </p>
          <p data-role="reasoning" class="opacity-80">
            {pair.reasoning || "The Assayer could not say."}
          </p>
        </li>
      </ul>
    </section>
    """
  end

  # The rules name a rung; nobody says "deep_meld" out loud.
  defp band(nil), do: ""
  defp band(name), do: name |> to_string() |> String.replace("_", " ")

  defp waiting(%{open_seats: 0, seat_limit: seat_limit}),
    do: "All #{seat_limit} seats taken"

  defp waiting(%{open_seats: 1}), do: "Waiting for 1 more"
  defp waiting(%{open_seats: open}), do: "Waiting for #{open} more"
end
