defmodule ThereishWeb.RailComponents do
  @moduledoc """
  The Rail: how the Ladder is drawn, in one place.

  The bands have been configuration since the first Page and drawn nowhere, so
  a 74 and a 76 felt like the same miss and "seven short of a Meld" — the one
  unit the table actually feels — was never said out loud. This module says it.

  Every boundary here is read from `Thereish.Ladder`, never written into the
  markup: the scale, the bands in order, and the one line where a Meld starts.
  A Rail that disagreed with the grade it draws would be worse than no Rail.

  What a band looks like is not here either. Each band carries its own
  `data-band`, and the colour behind that attribute is a theme token
  (`--band-close` and its five siblings) the badge and the closeness card read
  too, so the three cannot disagree about what a 54 looks like.
  """
  use ThereishWeb, :html

  alias Thereish.Ladder

  @words ~w(one two three four five six seven eight nine ten eleven twelve thirteen
            fourteen fifteen sixteen seventeen eighteen nineteen twenty)

  @doc """
  The Ladder drawn as one scale: its bands in order, the Meld line, this
  Attempt's Closeness as a marker on it, and each Seat's Call as a pin.

  The marker is drawn where the grade actually is, and the reveal's sequencer
  hook launches it from the left to that spot while counting the number on the
  same clock — one clock for both, so the pin and the number cannot disagree on
  the way up, and a screen running no hook at all still shows the truth. A
  reveal the Assayer could not grade draws the scale and no marker: there is
  nowhere honest to put it.

  `marks` are faint labelled pins for readings that are not the grade.
  """
  attr :mode, :atom, default: :phone, values: [:phone, :stage, :quiet]
  attr :closeness, :integer, default: nil
  attr :band, :atom, default: nil
  attr :melded?, :boolean, default: false
  attr :gap, :integer, default: nil

  attr :calls, :list,
    default: [],
    doc: "the view's reveal calls, each wearing its Seat's colour when it has one"

  attr :marks, :list, default: [], doc: "faint labelled pins: `%{closeness:, label:}`"

  def ladder_rail(assigns) do
    ~H"""
    <div
      data-role="ladder-rail"
      data-mode={@mode}
      data-band={@band}
      class={[
        "flex w-full flex-col items-stretch",
        if(@mode == :stage, do: "max-w-3xl gap-3 pt-7", else: "max-w-sm gap-2 pt-6")
      ]}
    >
      <div
        data-role="rail-track"
        class={[
          "relative flex w-full rounded-full",
          if(@mode == :stage, do: "h-4", else: "h-3")
        ]}
      >
        <div
          :for={rung <- rungs()}
          data-role="rail-band"
          data-band={rung.name}
          style={"width: #{rung.width}%"}
          class="rail-band h-full first:rounded-l-full last:rounded-r-full"
        >
        </div>

        <div
          data-role="meld-line"
          style={"left: #{position(Ladder.meld_threshold())}%"}
          class="absolute -top-1.5 -bottom-1.5 w-px bg-base-content/70"
        >
          <span class="absolute -top-4 left-1/2 -translate-x-1/2 text-[10px] font-bold uppercase tracking-[0.2em] opacity-70">
            Meld
          </span>
        </div>

        <span
          :if={@closeness}
          data-role="rail-marker"
          data-target={position(@closeness)}
          data-melded={to_string(@melded?)}
          style={"left: #{position(@closeness)}%"}
          class="rail-marker absolute -top-2 -bottom-2 w-1 -translate-x-1/2 rounded-full bg-base-content"
          aria-hidden="true"
        ></span>

        <span
          :for={call <- @calls}
          data-role="call-pin"
          data-seat={call[:seat_id]}
          data-band={call[:band]}
          style={"left: #{band_midpoint(call[:band])}%; --seat-color: #{colour(call)}"}
          title={"#{call[:name]} called #{words(call[:band])}"}
          class="call-pin absolute -top-3 size-2.5 -translate-x-1/2 rounded-full border"
        ></span>

        <span
          :for={mark <- @marks}
          data-role="rail-mark"
          style={"left: #{position(mark[:closeness])}%"}
          class="absolute -bottom-2 top-1/2 w-px -translate-x-1/2 border-l border-dashed border-base-content/50"
        >
          <span class="absolute -bottom-4 left-1/2 -translate-x-1/2 whitespace-nowrap text-[10px] uppercase tracking-widest opacity-50">
            {mark[:label]}
          </span>
        </span>
      </div>

      <p
        :if={short_by?(@gap)}
        data-role="short-by"
        class={[
          "text-center font-bold uppercase tracking-[0.2em] opacity-70",
          if(@mode == :stage, do: "text-base", else: "text-xs")
        ]}
      >
        {spell(@gap)} short
      </p>
    </div>
    """
  end

  @doc """
  The middle of a band, as a position on the scale — where a Call's pin sits,
  because a Call names a band and not a number.
  """
  @spec band_midpoint(atom() | nil) :: String.t()
  def band_midpoint(band) do
    case Enum.find(rungs(), &(&1.name == band)) do
      nil -> position(Ladder.meld_threshold())
      rung -> position((rung.floor + rung.ceiling) / 2)
    end
  end

  @doc """
  A small number in words, which is how the gap is said: "seven short", not
  "7 short". Past twenty the numeral reads better than the mouthful.
  """
  @spec spell(integer()) :: String.t()
  def spell(number) when number in 1..20, do: Enum.at(@words, number - 1)
  def spell(number), do: to_string(number)

  # Each band with the span it owns, in order, as a share of the scale. The last
  # band runs to the top of the scale — on the shipped Ladder that is the one
  # closeness a deep meld can be, so it draws as the line it is.
  defp rungs do
    bands = Ladder.bands()
    {_first, last} = Ladder.scale()
    ceilings = tl(Keyword.values(bands)) ++ [last]

    for {{name, floor}, ceiling} <- Enum.zip(bands, ceilings) do
      %{name: name, floor: floor, ceiling: ceiling, width: span(ceiling - floor)}
    end
  end

  # Where a closeness sits on the drawn scale, and how wide a span of it is,
  # both as percentages: the Ladder's numbers are not promised to be 0..100.
  defp position(value) do
    {first, last} = Ladder.scale()

    trim((value - first) * 100 / (last - first))
  end

  defp span(width) do
    {first, last} = Ladder.scale()

    trim(width * 100 / (last - first))
  end

  defp trim(percent) do
    rounded = Float.round(percent, 2)

    if rounded == Float.round(rounded, 0),
      do: to_string(round(rounded)),
      else: to_string(rounded)
  end

  # A gap worth saying. Further than this and "sixty short" is not a near miss
  # the table can feel, it is a different Page.
  defp short_by?(nil), do: false
  defp short_by?(gap), do: gap > 0 and gap <= 15

  defp colour(call), do: call[:colour] || "var(--color-primary, currentColor)"

  defp words(nil), do: ""
  defp words(band), do: band |> to_string() |> String.replace("_", " ")
end
