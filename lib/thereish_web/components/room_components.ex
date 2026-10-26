defmodule ThereishWeb.RoomComponents do
  @moduledoc """
  The parts of a Room that both the phones and the stage draw.

  Each of these is one component on purpose: "the stage lists who has joined;
  phones show the same roster" is a rule, and a rule with two implementations is
  a rule with two answers. The same goes for the Bookends and, most of all, for
  the reveal — the number the stage shouts and the number the phone shows have
  to be the same number.

  Everything here reads a snapshot and nothing here decides anything. What a
  Seat may see was settled by `Thereish.Game.view/2` before it got here.
  """
  use ThereishWeb, :html

  import ThereishWeb.RailComponents

  alias Thereish.Chronicle.Opinion
  alias Thereish.Mask

  attr :room, :map, required: true, doc: "a snapshot from Thereish.Rooms.snapshot/2"
  attr :mode, :atom, default: :phone

  def roster(assigns) do
    ~H"""
    <div
      data-role="roster"
      data-mode={if @mode == :stage, do: "stage"}
      class={[
        if(@mode == :stage,
          do: "flex flex-wrap items-center gap-x-4 gap-y-1 text-sm"
        )
      ]}
    >
      <ul class={
        if @mode == :stage,
          do: "flex flex-wrap items-center gap-x-3 gap-y-1",
          else: "flex flex-col gap-2"
      }>
        <.seat_badge
          :for={seat <- @room.seats}
          seat={seat}
          room={@room}
          mode={@mode}
        />
        <li
          :if={@room.seats == []}
          class={if @mode == :stage, do: "opacity-60", else: "text-lg opacity-60"}
        >
          Nobody yet
        </li>
      </ul>

      <p
        :if={waiting(@room)}
        data-role="open-seats"
        class={if @mode == :stage, do: "opacity-60", else: "mt-3 text-sm opacity-60"}
      >
        {waiting(@room)}
      </p>
    </div>
    """
  end

  @doc """
  Where to join: thereish.app, linked to this Room so a latecomer can follow one path.
  """
  attr :url, :string, required: true
  attr :class, :any, default: nil

  def join_at(assigns) do
    ~H"""
    <.link href={@url} data-role="join-url" class={["font-mono", @class]}>thereish.app</.link>
    """
  end

  @doc """
  Small uppercase caption, used for Attempt, Bookends, and section titles.
  """
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def caption(assigns) do
    ~H"""
    <p class={["text-center text-sm uppercase tracking-widest opacity-60", @class]} {@rest}>
      {render_slot(@inner_block)}
    </p>
    """
  end

  attr :seat, :map, required: true
  attr :room, :map, required: true
  attr :mode, :atom, default: :phone

  defp seat_badge(assigns) do
    ~H"""
    <li
      data-seat={@seat.id}
      data-committed={to_string(@seat.committed?)}
      class={[
        "flex items-center",
        if(@mode == :stage, do: "gap-1.5", else: "gap-2 text-lg")
      ]}
    >
      <.seat_mask seat={@seat} size={if @mode == :stage, do: :xs, else: :sm} />
      <span class={if @mode == :stage, do: "font-medium", else: ""}>
        {@seat.name}
      </span>
      <span
        :if={@mode != :stage and @seat.you?}
        class="text-sm opacity-60"
      >
        (you)
      </span>
      <span
        :if={@seat[:late?]}
        class={if @mode == :stage, do: "text-xs opacity-60", else: "text-sm opacity-60"}
      >
        (watching)
      </span>
      <span
        :if={!@seat[:late?] and @seat.committed? and mid_page?(@room)}
        class={[
          "opacity-60",
          if(@mode == :stage, do: "text-xs font-semibold", else: "text-sm")
        ]}
      >
        {if @mode == :stage, do: "✓", else: "has written a bridge"}
      </span>
    </li>
    """
  end

  @doc """
  A Seat's Mask, drawn the one way every Room screen draws it.

  The Seat comes from `Thereish.Game.view/2`, which has already decided which
  Mask this viewer may see. There are three looks: the picture once it is
  drawn, the card face down when the Seat's Give has landed before the first
  reveal, and the Seat's colour dot otherwise (`:dot` or no Mask yet).

  `:xs` and `:sm` are badge sizes and draw a bare dot. From `:md` up every look
  fills the same square, so a row of Masks lines up whichever look each Seat
  wears; `:xl` is the one Mask on its own card, and its dot stays bare.
  """
  attr :seat, :map, required: true, doc: "a Seat from Thereish.Game.view/2"
  attr :size, :atom, required: true, values: [:xs, :sm, :md, :lg, :xl]

  def seat_mask(assigns) do
    assigns =
      assign(assigns,
        url: Mask.url(assigns.seat[:mask]),
        colour: seat_colour(assigns.seat)
      )

    ~H"""
    <%= cond do %>
      <% @url -> %>
        <img
          src={@url}
          alt={@seat.name}
          data-role="seat-mask"
          class={["object-cover", picture_class(@size)]}
          style={"--seat-color: #{@colour}"}
        />
      <% @seat[:mask] == :face_down -> %>
        <span
          data-role="mask-face-down"
          data-seat={@seat.id}
          class={["flex items-center justify-center opacity-80", face_down_class(@size)]}
          style={"--seat-color: #{@colour}; border-color: var(--seat-color); background-color: color-mix(in oklab, var(--seat-color) 15%, transparent); color: var(--seat-color);"}
          title="Mask face down"
        >
          🂠
        </span>
      <% @size in [:md, :lg] -> %>
        <span
          class={["flex items-center justify-center", tile_class(@size)]}
          style={"--seat-color: #{@colour}"}
        >
          <.colour_dot colour={@colour} class="size-6 shadow-sm" />
        </span>
      <% true -> %>
        <.colour_dot colour={@colour} class={dot_class(@size)} />
    <% end %>
    """
  end

  @doc """
  The colour a Seat wears on the Room screens, falling back to the theme's
  primary colour for a Seat that has none.
  """
  def seat_colour(seat), do: seat[:colour] || "var(--color-primary, currentColor)"

  attr :colour, :string, required: true
  attr :class, :string, required: true

  defp colour_dot(assigns) do
    ~H"""
    <span
      data-role="seat-colour-dot"
      class={["rounded-full", @class]}
      style={"background-color: #{@colour}"}
      aria-hidden="true"
    ></span>
    """
  end

  defp picture_class(:xs), do: "size-3.5 rounded border border-base-300"
  defp picture_class(:sm), do: "size-5 rounded border border-base-300"
  defp picture_class(:md), do: "size-14 rounded-lg border border-base-300 shadow-sm"
  defp picture_class(:lg), do: "size-16 rounded-xl border-2 border-(--seat-color) shadow-md"
  defp picture_class(:xl), do: "size-24 rounded-xl border border-base-300 shadow-md"

  defp face_down_class(:xs), do: "size-3 rounded border text-[10px]"
  defp face_down_class(:sm), do: "size-4 rounded border text-[10px]"
  defp face_down_class(:md), do: "size-14 rounded-xl border-2 text-2xl shadow-sm"
  defp face_down_class(:lg), do: "size-16 rounded-xl border-2 text-2xl shadow-md"
  defp face_down_class(:xl), do: "size-24 rounded-xl border-2 text-4xl shadow-md"

  defp tile_class(:md), do: "size-14"

  defp tile_class(:lg),
    do: "size-16 rounded-xl border-2 border-(--seat-color) bg-base-200 shadow-md"

  defp dot_class(:xs), do: "size-1.5"
  defp dot_class(:sm), do: "size-2"
  defp dot_class(:xl), do: "size-5"

  attr :room, :map, required: true
  attr :mode, :atom, default: :phone

  @doc """
  The words the Page hangs between, shown to everyone at once.

  A wrapping row of word chips under the Bookends caption at any count, with an
  optional Mask beside a carried word. First-Attempt Bookends stay unattributed.
  """
  def bookends(assigns) do
    chips = bookend_chips(assigns.room)
    assigns = assign(assigns, :chips, chips)

    ~H"""
    <div
      :if={@chips != []}
      class={[
        "flex flex-col items-center",
        if(@mode == :stage, do: "gap-2", else: "gap-3")
      ]}
    >
      <.caption data-role="bookends-caption">
        Bookends
      </.caption>
      <div
        data-role="bookends"
        class={[
          "flex flex-wrap items-center justify-center",
          if(@mode == :stage, do: "gap-2 sm:gap-3", else: "gap-2 sm:gap-3")
        ]}
      >
        <span
          :for={chip <- @chips}
          data-role="bookend-chip"
          class={[
            "inline-flex items-center rounded-lg bg-base-200 font-semibold tracking-tight",
            if(@mode == :stage,
              do: "gap-1.5 px-3 py-1.5 sm:px-4 sm:py-2 text-xl sm:text-2xl",
              else: "gap-1.5 px-3 py-2 text-2xl sm:text-3xl"
            )
          ]}
        >
          <img
            :if={mask_url(chip)}
            src={mask_url(chip)}
            alt=""
            data-role="bookend-mask"
            class={[
              "rounded object-cover border border-base-300",
              if(@mode == :stage, do: "size-4 sm:size-5", else: "size-5")
            ]}
          />
          {bookend_word(chip)}
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Joins words with commas and a final "and": two stay "cairn and beacon", six
  become "cairn, beacon, wharf, signal, torch and lamp".
  """
  defdelegate join_and(words), to: Thereish.Game

  defp bookend_chips(%{bookend_chips: chips}) when is_list(chips) and chips != [], do: chips
  defp bookend_chips(%{bookends: bookends}) when is_list(bookends), do: bookends
  defp bookend_chips(_), do: []

  defp bookend_word(%{word: word}) when is_binary(word), do: word
  defp bookend_word(%{"word" => word}) when is_binary(word), do: word
  defp bookend_word(word) when is_binary(word), do: word
  defp bookend_word(_), do: ""

  defp mask_url(%{mask: mask}), do: Mask.url(mask)
  defp mask_url(_), do: nil

  attr :room, :map, required: true
  attr :mode, :atom, default: :phone

  @doc """
  The Nudges this Page has spent: one public word each, struck through.

  A chip is struck through because that is what a Nudge is — the word it names
  is barred for the rest of the Page, for everyone, the Seat that spent it
  included. A chip from an earlier Attempt dims rather than leaves, because the
  word is still barred. On the Stage the word is large and its Seat is named:
  a Nudge landing is theatre, not a notification.
  """
  def nudges(assigns) do
    assigns = assign(assigns, :chips, nudge_chips(assigns.room))

    ~H"""
    <div
      :if={@chips != []}
      class={[
        "flex flex-col items-center",
        if(@mode == :stage, do: "gap-2", else: "gap-3")
      ]}
    >
      <.caption data-role="nudges-caption">
        Nudges
      </.caption>
      <div
        data-role="nudges"
        class="flex flex-wrap items-start justify-center gap-2 sm:gap-3"
      >
        <div
          :for={chip <- @chips}
          data-role="nudge-chip"
          data-seat={chip.seat_id}
          data-attempt={chip.attempt}
          data-earlier={to_string(earlier_nudge?(@room, chip))}
          style={"--seat-color: #{chip.colour}; border-color: var(--seat-color); background-color: color-mix(in oklab, var(--seat-color) 12%, transparent);"}
          class={[
            "flex flex-col items-center gap-1 rounded-lg border",
            if(@mode == :stage, do: "px-4 py-2", else: "px-3 py-2"),
            earlier_nudge?(@room, chip) && "opacity-50"
          ]}
        >
          <p
            :if={@mode == :stage}
            data-role="nudge-by"
            class="text-xs uppercase tracking-widest opacity-70"
          >
            {chip.name} nudges
          </p>
          <div class="flex items-center gap-1.5">
            <.seat_mask
              :if={chip.seat}
              seat={chip.seat}
              size={if @mode == :stage, do: :sm, else: :xs}
            />
            <span class={[
              "font-semibold tracking-tight line-through",
              if(@mode == :stage, do: "text-2xl sm:text-3xl", else: "text-xl")
            ]}>
              {chip.word}
            </span>
            <span
              data-role="nudge-spent"
              class="rounded-full border border-current px-1.5 text-[10px] font-bold uppercase tracking-widest opacity-80"
            >
              Spent
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Each Nudge with the Seat that spent it, so a chip can wear that Seat's Mask
  # and colour. The Game says who nudged and nothing about how a Seat looks.
  defp nudge_chips(room) do
    seats = Map.new(room[:seats] || [], &{&1.id, &1})

    for nudge <- room[:nudges] || [] do
      seat = seats[nudge.seat_id]

      Map.merge(nudge, %{seat: seat, colour: seat_colour(seat || %{})})
    end
  end

  defp earlier_nudge?(room, chip), do: chip.attempt < room.attempt.number

  attr :room, :map, required: true

  @doc """
  Which try this is, and how many the Page gets.

  Shown while a Page is being played and not once it has ended, because at the
  end the number that matters is which attempt it landed on rather than how many
  are left.
  """
  def attempt(assigns) do
    ~H"""
    <.caption
      :if={@room.phase in [:bridging, :assaying, :reveal]}
      data-role="attempt"
    >
      Attempt {@room.attempt.number} of {@room.attempt.of}
    </.caption>
    """
  end

  attr :room, :map, default: %{}
  attr :mode, :atom, default: :phone

  @doc """
  The Author writing: pulsing beat meter while Gemini writes the Bookends.
  """
  def author_writing(assigns) do
    ~H"""
    <div
      data-role="beat-meter"
      data-step={@room[:author_step] || :writing}
      class="flex flex-col items-center gap-2"
    >
      <div class="flex items-center gap-2" aria-hidden="true">
        <span class="size-2.5 rounded-full bg-primary animate-ping"></span>
        <span class="size-2.5 rounded-full bg-primary/70 animate-pulse"></span>
        <span class="size-2.5 rounded-full bg-primary/40 animate-pulse"></span>
      </div>
      <p class="text-xs font-semibold tracking-widest uppercase opacity-60">
        The Author is writing
      </p>
    </div>
    <p class={if @mode == :stage, do: "text-2xl font-semibold", else: "text-lg font-medium"}>
      {if @room[:author_step] == :still_writing,
        do: "The Author is still writing...",
        else: "The Author is reading your Gives..."}
    </p>
    """
  end

  attr :room, :map, required: true
  attr :seat, :map, default: nil
  attr :mode, :atom, default: :phone

  @doc """
  The pause while the Assayer reads the Bridges.

  Shown when the Room has moved into `:assaying` — which means every Bridge has
  been committed and the beat is running.

  The Beat is also the Call window, so this is where the phone stops being
  three pulsing dots: a Seat that may Call gets the buttons instead, and every
  screen shows who has called what, because a Call being public is the whole of
  the mechanic.
  """
  def assaying(assigns) do
    ~H"""
    <div
      :if={@room.phase == :assaying}
      data-role="phase"
      data-step={@room.assayer_step || :grading}
      class="flex flex-col items-center justify-center gap-3 text-center"
    >
      <div
        :if={
          beat_dots?(@room, @mode) and
            (is_nil(@room.assayer_step) or @room.assayer_step == :grading)
        }
        data-role="beat-meter"
        class="flex flex-col items-center gap-2"
      >
        <div class="flex items-center gap-2" aria-hidden="true">
          <span class="size-2.5 rounded-full bg-primary animate-ping"></span>
          <span class="size-2.5 rounded-full bg-primary/70 animate-pulse"></span>
          <span class="size-2.5 rounded-full bg-primary/40 animate-pulse"></span>
        </div>
        <p class="text-xs font-semibold tracking-widest uppercase opacity-60">
          The Beat — holding the breath
        </p>
      </div>

      <.call_bands room={@room} seat={@seat} mode={@mode} />

      <p class="text-lg opacity-70">
        {waiting_line(@room.assayer_step)}
      </p>
    </div>
    """
  end

  # The Beat's three dots were the phone's whole job at the climax. When this
  # phone may Call, the buttons are the job and the dots under them would be
  # noise; the Stage keeps them, because the Stage never calls.
  defp beat_dots?(room, mode), do: mode == :stage or not may?(room, :call)

  attr :room, :map, required: true
  attr :seat, :map, default: nil
  attr :mode, :atom, default: :phone

  @doc """
  Call it: the band a Seat names during the Beat, before the number arrives,
  and the row of who has called what.

  A Call settles nothing and counts for nothing — nothing is totalled here or
  anywhere, and a Seat that does not call simply has no pin on the Rail. The
  row renders on every screen the Beat is on, the Stage included, because the
  public read is the point; only a phone holding a Seat gets the buttons.
  """
  def call_bands(assigns) do
    assigns =
      assigns
      |> assign(:calls, coloured_calls(assigns.room, assigns.room[:calls]))
      |> assign(:buttons?, assigns.mode != :stage and may?(assigns.room, :call))
      |> assign(:yours, your_call(assigns.room, assigns.seat))

    ~H"""
    <div
      :if={@buttons? or @calls != []}
      data-role="call-bands"
      data-mode={@mode}
      class="flex w-full flex-col items-center gap-2"
    >
      <.caption :if={@buttons?} data-role="call-caption">
        Call it.
      </.caption>

      <div :if={@buttons?} class="flex w-full flex-col gap-2">
        <button
          :for={band <- @room.callable_bands}
          type="button"
          phx-click="call"
          phx-value-band={band}
          data-role="call-band"
          data-band={band}
          data-called={to_string(@yours == band)}
          class={[
            "btn min-h-11 w-full text-base font-bold uppercase tracking-widest",
            if(@yours == band,
              do: "btn-primary shadow-sm",
              else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
            )
          ]}
        >
          {band(band)}
        </button>
      </div>

      <div
        :if={@calls != []}
        data-role="call-row"
        class="flex flex-wrap items-center justify-center gap-2"
      >
        <span
          :for={call <- @calls}
          data-role="called"
          data-seat={call.seat_id}
          data-band={call.band}
          style={"--seat-color: #{call.colour}; border-color: var(--seat-color); background-color: color-mix(in oklab, var(--seat-color) 12%, transparent);"}
          class={[
            "inline-flex items-center gap-1.5 rounded-full border px-3 py-1 font-medium",
            if(@mode == :stage, do: "text-base", else: "text-xs")
          ]}
        >
          {call.name} called
          <span class="font-bold uppercase tracking-widest">{band(call.band)}</span>
        </span>
      </div>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :seat, :map, default: nil

  @doc """
  The noise at the punchline: four words a Seat may send at a reveal.

  The vocabulary is the Game's and is read from there, the way the Rail reads
  the Ladder's bands, so there is one list of them. Nothing is totalled: the
  reactions are kept in the Chronicle and counted nowhere, on no screen, ever
  (ADR-0023). A Seat's latest word replaces its last, so there is only one.
  """
  def reactions(assigns) do
    assigns =
      assigns
      |> assign(:vocabulary, Thereish.Game.reactions())
      |> assign(:yours, your_reaction(assigns.room, assigns.seat))

    ~H"""
    <div
      data-role="reactions"
      class="flex flex-wrap items-center justify-center gap-2"
    >
      <button
        :for={reaction <- @vocabulary}
        type="button"
        phx-click="react"
        phx-value-reaction={reaction}
        data-role="reaction"
        data-reaction={reaction}
        data-chosen={to_string(@yours == reaction)}
        class={[
          "btn btn-sm min-h-11 text-xs font-bold uppercase tracking-widest",
          if(@yours == reaction,
            do: "btn-primary shadow-sm",
            else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
          )
        ]}
      >
        {band(reaction)}
      </button>
    </div>
    """
  end

  # The one word this Seat has sent at this reveal, if it has sent one.
  defp your_reaction(_room, nil), do: nil

  defp your_reaction(room, seat) do
    case Enum.find(room[:reactions] || [], &(&1.seat_id == seat.id)) do
      nil -> nil
      reaction -> reaction.reaction
    end
  end

  # Which band this Seat has called, if it has called one. The latest Call
  # wins, so there is only ever the one.
  defp your_call(_room, nil), do: nil

  defp your_call(room, seat) do
    case Enum.find(room[:calls] || [], &(&1.seat_id == seat.id)) do
      nil -> nil
      call -> call.band
    end
  end

  attr :room, :map, required: true
  attr :mode, :atom, default: :phone

  @doc """
  The Assayer's two readings of the same Bridges, on the rare reveal where they
  contradict each other far enough to say so (ADR-0024).

  This is the one place in the game the Assayer's reasoning reaches a screen,
  and the contradiction is the whole reason: the table is not being told what
  the grade means, it is being handed two arguments and asked to settle them,
  which is the one authority the players have always had. The recorded Verdict
  is still the mean, and only a unanimous Overrule rewrites it.

  It renders on the phone, on the Stage and on a quiet phone — the held phone
  gets the words while the Stage holds the spectacle — and nowhere at all in a
  Room that has turned Split readings off.
  """
  def split_reading(assigns) do
    assigns = assign(assigns, :split, split_shown(assigns.room))

    ~H"""
    <div
      :if={@split}
      data-role="split-reading"
      class={[
        "flex flex-col items-center gap-1 text-center w-full",
        if(@mode == :stage, do: "max-w-3xl", else: "max-w-sm")
      ]}
    >
      <p
        data-role="split-headline"
        class={[
          "font-bold uppercase tracking-widest opacity-70",
          if(@mode == :stage, do: "text-sm", else: "text-xs")
        ]}
      >
        The Assayer graded this twice — {@split.forward}, and {@split.reverse}.
      </p>
      <p
        data-role="split-forward"
        class={["opacity-80", if(@mode == :stage, do: "text-base", else: "text-sm")]}
      >
        {@split.reasoning}
      </p>
      <p
        :if={@split[:reasoning_reverse]}
        data-role="split-reverse"
        class={["opacity-80", if(@mode == :stage, do: "text-base", else: "text-sm")]}
      >
        {@split[:reasoning_reverse]}
      </p>
    </div>
    """
  end

  @doc """
  The Split reading this Room is showing, or nil.

  Both have to be there: the Verdict's two readings and the Room's own fact.
  The Game is ignorant of Room facts and stays that way, so the two are put
  together here, where the Rail's ghost pins and the one-tap Overrule read the
  same answer.
  """
  @spec split_shown(map()) :: map() | nil
  def split_shown(room) do
    if Map.get(room, :split_readings, true) != false, do: (room[:reveal] || %{})[:split]
  end

  # The two readings as ghost pins, drawn on the same scale as the grade so the
  # disagreement is a distance rather than a claim. Labelled with their own
  # numbers, because what the pin says is where it is.
  defp split_marks(room) do
    case split_shown(room) do
      nil -> []
      split -> for n <- [split.forward, split.reverse], do: %{closeness: n, label: to_string(n)}
    end
  end

  attr :room, :map, required: true
  attr :seat, :map, default: nil
  attr :mode, :atom, default: :phone

  @doc """
  The reveal, performed: the Bridges flipping face up one at a time, each word
  landing before the name of whoever wrote it, then the marker climbing the
  Rail with the number counting beside it, then the punchline quip.

  One hook runs all of it off one clock, and the whole performance is absorbed
  by the hold Pacing arms, never added on top of it.

  The phone's own job at the punchline is the noise: four words to shout and
  nothing to fill in. The survey about the grader that used to sit here has
  moved to the closing card (`ending/1`).
  """
  def reveal(assigns) do
    standard_reveal(assigns)
  end

  defp standard_reveal(assigns) do
    presentation = assigns.room.reveal && closeness_presentation(assigns.room.reveal)
    sequence = reveal_sequence()

    assigns =
      assigns
      |> assign(:presentation, presentation)
      |> assign(:sequence, sequence)

    ~H"""
    <section
      :if={@room.reveal}
      id="reveal-performance"
      phx-hook=".RevealSequence"
      data-role="reveal"
      data-arrival={reveal_arrival(@room.reveal)}
      data-mode={@mode}
      data-stagger={@sequence[:stagger]}
      data-cap={@sequence[:cap]}
      data-settle={@sequence[:settle]}
      data-melded={to_string(@room.reveal[:melded?] == true)}
      class={[
        "flex flex-col items-center w-full mx-auto",
        if(@mode == :stage, do: "gap-[clamp(0.5rem,1.8vh,1.5rem)] max-w-4xl", else: "gap-8 max-w-xl")
      ]}
    >
      <div
        data-role="comparison"
        class={[
          "flex flex-wrap items-stretch justify-center w-full",
          if(@mode == :stage, do: "gap-2 sm:gap-3", else: "gap-3 sm:gap-4")
        ]}
      >
        <div
          :for={bridge <- @room.reveal.bridges}
          data-bridge={bridge.seat_id}
          data-you={to_string(you?(@seat, bridge))}
          class={[
            "flex flex-1 flex-col items-center justify-center gap-1 rounded-xl border text-center transition-all duration-300",
            if(@mode == :stage,
              do: "min-w-[120px] max-w-[240px] basis-40 sm:basis-48 p-2.5 sm:p-3",
              else: "min-w-[120px] sm:min-w-44 p-4"
            ),
            if(you?(@seat, bridge),
              do: "border-primary/60 bg-primary/5 ring-2 ring-primary/20",
              else: "border-base-300 bg-base-100 shadow-sm"
            )
          ]}
        >
          <div
            data-role="bridge-name"
            class="flex items-center gap-1.5 text-xs uppercase tracking-wider opacity-60"
          >
            <span>{bridge.name}</span>
            <span :if={you?(@seat, bridge)} class="font-bold text-primary">(you)</span>
          </div>
          <span class={[
            "font-bold tracking-tight",
            if(@mode == :stage, do: "text-2xl sm:text-3xl md:text-4xl", else: "text-2xl sm:text-3xl")
          ]}>
            {bridge.bridge}
          </span>
        </div>
      </div>

      <div
        :if={@mode != :quiet && @room.reveal.closeness}
        data-role="closeness-display"
        data-band={@room.reveal.band}
        class={[
          "flex flex-col items-center justify-center rounded-2xl transition-all duration-500 w-full max-w-sm text-center",
          if(@mode == :stage, do: "px-6 py-2 sm:py-3", else: "px-8 py-6"),
          @presentation.container_class
        ]}
      >
        <span
          id="reveal-closeness"
          data-role="closeness"
          data-target={@room.reveal.closeness}
          class={[
            "font-black tracking-tighter tabular-nums leading-none select-none",
            if(@mode == :stage, do: "text-7xl sm:text-8xl md:text-9xl", else: "text-7xl sm:text-8xl"),
            @presentation.number_class
          ]}
        >
          {@room.reveal.closeness}
        </span>

        <div class={[
          "flex flex-col items-center",
          if(@mode == :stage, do: "mt-1 sm:mt-1.5 gap-1", else: "mt-3 gap-1.5")
        ]}>
          <span
            data-role="band"
            class={[
              "font-extrabold uppercase tracking-widest rounded-full",
              if(@mode == :stage,
                do: "text-sm sm:text-base md:text-lg px-3 py-0.5",
                else: "text-lg sm:text-xl px-4 py-1"
              ),
              @presentation.badge_class
            ]}
          >
            {band(@room.reveal.band)}
          </span>
        </div>
      </div>

      <.ladder_rail
        mode={@mode}
        closeness={@room.reveal.closeness}
        band={@room.reveal.band}
        melded?={@room.reveal[:melded?] == true}
        gap={@room.reveal[:gap]}
        calls={coloured_calls(@room, @room.reveal[:calls])}
        marks={split_marks(@room)}
      />

      <.split_reading room={@room} mode={@mode} />

      <p
        :if={@mode == :quiet}
        data-role="look-up"
        class="text-sm font-bold uppercase tracking-[0.3em] opacity-70"
      >
        Look up.
      </p>

      <div
        :if={@mode != :quiet && @room.reveal.closeness == nil}
        data-role="no-verdict"
        class="flex flex-col items-center gap-3 rounded-2xl border border-primary/30 bg-base-200/60 p-6 sm:p-8 text-center max-w-md shadow-sm"
      >
        <div class="flex items-center gap-2 text-xs font-bold uppercase tracking-widest text-primary">
          <span>The Assayer steps aside</span>
        </div>
        <p class="text-2xl sm:text-3xl font-bold tracking-tight">
          No verdict. This one is yours to call.
        </p>
        <p class="text-sm opacity-70 max-w-sm">
          The clock ran out and the machine stepped aside. You on the couch decide whether this was a Meld.
        </p>
      </div>

      <p
        :if={@mode != :quiet && Map.get(@room, :quips, true) && @room.reveal.quip}
        data-role="quip"
        class={[
          "font-serif italic font-medium leading-snug max-w-2xl text-center",
          if(@mode == :stage,
            do: "text-xl sm:text-2xl md:text-3xl text-base-content",
            else: "text-xl sm:text-2xl text-base-content/90"
          )
        ]}
      >
        {@room.reveal.quip}
      </p>

      <div
        :if={
          @mode == :stage and @room[:first_revealed?] == true and @room.phase != :closed and
            is_list(@room[:seats]) and @room[:seats] != []
        }
        data-role="stage-masks"
        class="flex flex-wrap items-center justify-center gap-4 my-2"
      >
        <div
          :for={seat <- @room[:seats] || []}
          data-role="stage-mask"
          data-seat={seat.id}
          class="flex flex-col items-center gap-1"
        >
          <.seat_mask seat={seat} size={:lg} />
          <span class="text-xs font-semibold opacity-75">{seat.name}</span>
        </div>
      </div>

      <.reactions
        :if={@mode in [:phone, :quiet] && may?(@room, :react)}
        room={@room}
        seat={@seat}
      />

      <div
        :if={(@room[:closed] || @room.phase == :closed) && @room.reveal[:gives] not in [nil, []]}
        data-role="gives"
        class={[
          "flex flex-col items-center w-full",
          if(@mode == :stage, do: "gap-2", else: "gap-3")
        ]}
      >
        <.caption>Gives</.caption>
        <div class="flex flex-wrap items-stretch justify-center gap-3 sm:gap-4 w-full">
          <div
            :for={give <- @room.reveal.gives}
            data-role="give"
            data-seat={give[:seat_id]}
            class={[
              "flex flex-col items-center gap-2 rounded-xl border border-base-300 bg-base-100 p-3 text-center shadow-sm",
              if(@mode == :stage,
                do: "min-w-[7rem] max-w-[11rem]",
                else: "min-w-[8rem] max-w-[12rem]"
              )
            ]}
          >
            <img
              :if={mask_url(give)}
              src={mask_url(give)}
              alt={"Mask for #{give[:name] || give[:seat_name]}"}
              data-role="give-mask"
              class={[
                "rounded-xl object-cover border-2 border-base-300 shadow-md",
                if(@mode == :stage, do: "size-16 sm:size-20", else: "size-20")
              ]}
            />
            <p class="text-sm font-semibold uppercase tracking-wide opacity-70">
              {give[:name] || give[:seat_name]}
            </p>
            <p class="text-lg font-semibold leading-snug">{give[:text] || give[:give]}</p>
          </div>
        </div>
      </div>

      <p :if={@mode == :stage} class="text-xs font-semibold uppercase tracking-widest opacity-50">
        The couch has the call · Use your phones to continue or overrule
      </p>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".RevealSequence">
        export default {
          mounted() {
            // One hook for the whole performance. The cards, the marker and the
            // number cannot drift apart if there is only one clock, and the run
            // is sized from the numbers Pacing used to arm the hold, so the
            // button never comes alive in the middle of the punchline.
            const el = this.el
            const dataset = (name, fallback) => {
              const parsed = parseInt(el.dataset[name], 10)
              return isNaN(parsed) ? fallback : parsed
            }

            this.cards = Array.from(el.querySelectorAll("[data-bridge]"))
            this.names = this.cards.map((card) => card.querySelector('[data-role="bridge-name"]'))
            this.number = el.querySelector('[data-role="closeness"]')
            this.display = el.querySelector('[data-role="closeness-display"]')
            this.badge = el.querySelector('[data-role="band"]')
            this.rail = el.querySelector('[data-role="ladder-rail"]')
            this.marker = el.querySelector('[data-role="rail-marker"]')
            this.pins = Array.from(el.querySelectorAll('[data-role="call-pin"]'))
            this.marks = Array.from(el.querySelectorAll('[data-role="rail-mark"]'))
            this.split = el.querySelector('[data-role="split-reading"]')
            this.shortBy = el.querySelector('[data-role="short-by"]')
            this.target = this.number ? parseInt(this.number.dataset.target, 10) : NaN

            // Reduced motion is about motion and nothing else: every element
            // ends in its final, legible place, it simply never travels there.
            // A Stage that is not being looked at gets no animation frames, so
            // its performance would start whenever someone looks; it lands in
            // its final state instead.
            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches || document.hidden) {
              this.setFinalState()
              return
            }

            const cap = dataset("cap", 1400)
            const settle = dataset("settle", 900)
            const seats = Math.max(1, this.cards.length)
            // The whole flip run fits under the cap at any Seat count: eight
            // Seats wait no longer for the number than two do.
            const stagger = Math.min(dataset("stagger", 260), cap / seats)
            const flip = stagger * seats

            this.cards.forEach((card, i) => {
              this.play(card, [{opacity: 0, transform: "rotateY(180deg)"}, {opacity: 1}], {
                duration: 360,
                delay: i * stagger
              })
            })

            // The word lands before its author — the guess-whose beat, bought
            // with no extra input from anybody.
            this.names.forEach((name, i) => {
              this.play(name, [{opacity: 0}, {opacity: 1}], {
                duration: 220,
                delay: i * stagger + 180
              })
            })

            this.play(this.display, [{opacity: 0, transform: "translateY(8px)"}, {opacity: 1}], {
              duration: Math.max(160, settle * 0.25),
              delay: flip
            })
            this.play(this.rail, [{opacity: 0, transform: "scaleX(0.97)"}, {opacity: 1}], {
              duration: Math.max(160, settle * 0.25),
              delay: flip
            })
            this.pins.forEach((pin, i) => {
              this.play(pin, [{opacity: 0, transform: "translate(-50%, -0.5rem) scale(0.6)"}, {opacity: 1}], {
                duration: 240,
                delay: flip + 120 * (i + 1)
              })
            })

            const launch = flip + settle * 0.1
            const climb = Math.max(260, settle * 0.7)

            if (this.marker) {
              const place = this.marker.dataset.target
              const over = Math.min(100, parseFloat(place) + 3)
              this.play(this.marker, [{left: "0%"}, {left: over + "%"}, {left: place + "%"}], {
                duration: climb,
                delay: launch
              })
            }
            if (!isNaN(this.target)) this.count(launch, climb)

            this.play(this.badge, [{opacity: 0, transform: "scale(0.9)"}, {opacity: 1}], {
              duration: 240,
              delay: launch + climb * 0.6
            })
            this.play(this.shortBy, [{opacity: 0}, {opacity: 1}], {
              duration: Math.max(140, settle * 0.2),
              delay: flip + settle * 0.8
            })

            // A Split reading is the aftermath and never the headline: the two
            // ghost pins land once the grade has parked, and the sentences
            // after them.
            this.marks.forEach((mark, i) => {
              this.play(mark, [{opacity: 0}, {opacity: 1}], {
                duration: 240,
                delay: launch + climb + 120 * (i + 1)
              })
            })
            this.play(this.split, [{opacity: 0}, {opacity: 1}], {
              duration: 240,
              delay: launch + climb + 120 * (this.marks.length + 1)
            })

            if (el.dataset.melded === "true") this.flash(launch + climb * 0.75)
          },

          destroyed() {
            if (this.flashTimer) clearTimeout(this.flashTimer)
            if (this.landTimer) clearTimeout(this.landTimer)
          },

          // Every step is the same shape: hold the element where it starts until
          // its moment, then let the CSS it already carries be where it lands.
          play(node, frames, timing) {
            if (!node) return
            node.animate(frames, Object.assign({easing: "cubic-bezier(.16,1,.3,1)", fill: "backwards"}, timing))
          },

          count(delay, duration) {
            const node = this.number
            const target = this.target
            node.textContent = "0"
            let start = null

            const tick = (now) => {
              if (start === null) start = now + delay
              if (now < start) return requestAnimationFrame(tick)

              const progress = Math.min((now - start) / duration, 1)
              const eased = 1 - Math.pow(1 - progress, 3)
              node.textContent = Math.round(eased * target)

              if (progress < 1) requestAnimationFrame(tick)
              else node.textContent = target
            }
            requestAnimationFrame(tick)
            // Frames can be throttled; the clock cannot. The number is the
            // grade by the time the climb is over, whatever the frames did.
            this.landTimer = setTimeout(() => (node.textContent = target), delay + duration + 50)
          },

          // A Meld is the one arrival the whole room gets: one flash, over the
          // whole screen, touching nothing.
          flash(delay) {
            this.flashTimer = setTimeout(() => {
              const flash = document.createElement("div")
              flash.dataset.role = "meld-flash"
              flash.style.cssText =
                "position:fixed;inset:0;z-index:50;pointer-events:none;" +
                "background:radial-gradient(circle at 50% 45%, color-mix(in oklab, var(--color-primary) 40%, transparent), transparent 65%);"
              document.body.appendChild(flash)
              const anim = flash.animate([{opacity: 0}, {opacity: 1}, {opacity: 0}], {duration: 420, easing: "ease-out"})
              anim.onfinish = () => flash.remove()
              anim.oncancel = () => flash.remove()
            }, delay)
          },

          setFinalState() {
            if (!isNaN(this.target)) this.number.textContent = this.target
          }
        }
      </script>
    </section>
    """
  end

  attr :room, :map, required: true
  attr :seat, :map, default: nil

  def fairness_controls(assigns) do
    ~H"""
    <div
      data-role="fairness-controls"
      class="flex flex-col items-center gap-2 pt-2"
    >
      <span class="text-xs font-semibold uppercase tracking-wider opacity-60">
        Was this grade fair?
      </span>
      <div class="flex items-center gap-2">
        <button
          :for={label <- Opinion.labels()}
          type="button"
          phx-click="fairness_tap"
          phx-value-label={label}
          data-role={"tap-#{String.replace(label, "_", "-")}"}
          data-tap={label}
          class={[
            "btn btn-sm text-xs font-medium transition-all",
            if(your_fairness_tap(@room, @seat) == label,
              do: chosen_opinion_class(label),
              else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
            )
          ]}
        >
          {String.capitalize(Opinion.human(label))}
        </button>
      </div>
      <%= if tap = your_fairness_tap(@room, @seat) do %>
        <div data-role="your-tap" class="flex items-center gap-1.5 text-xs text-primary font-medium">
          <span data-role="seat-tap" class="font-semibold capitalize">
            {Opinion.human(tap)}
          </span>
          recorded
        </div>
      <% end %>
    </div>
    """
  end

  attr :room, :map, required: true

  @doc """
  The overrule banner: visible on both phones and the stage while a proposal is
  pending, showing the joint ruling once agreed, and saying who declined one for
  the rest of the Attempt — a proposal that simply vanished read as a bug on a
  couch, which is not what a Seat answering for the table deserves.
  """
  def overrule_banner(assigns) do
    ~H"""
    <div
      :if={@room.overrule && @room.overrule.pending?}
      data-role="overrule-banner"
      class="flex flex-col items-center gap-2 rounded-lg border border-primary/30 bg-base-200/50 p-4 text-center"
    >
      <p
        :if={may?(@room, :vote_overrule) && @room.overrule.you_proposed?}
        data-role="overrule-pending"
      >
        You proposed an overrule. Waiting for everyone to agree.
      </p>

      <div
        :if={may?(@room, :vote_overrule) && !@room.overrule.you_agreed?}
        data-role="overrule-vote"
        class="flex flex-col items-center gap-3"
      >
        <p data-role="overrule-pending">
          <span class="font-semibold">{@room.overrule.proposer_name}</span>
          proposed overruling this grade to {proposed_grade(@room.overrule)}.
        </p>
        <div class="flex gap-3">
          <.button phx-click="agree_overrule" data-role="agree-overrule" variant="primary">
            Agree
          </.button>
          <.button phx-click="decline_overrule" data-role="decline-overrule">
            Decline
          </.button>
        </div>
      </div>

      <p
        :if={
          may?(@room, :vote_overrule) && @room.overrule.you_agreed? &&
            !@room.overrule.you_proposed?
        }
        data-role="overrule-pending"
      >
        You agreed. Waiting for everyone to agree.
      </p>

      <p :if={!may?(@room, :vote_overrule)} data-role="overrule-pending" class="opacity-80">
        <span class="font-semibold">{@room.overrule.proposer_name}</span>
        proposed an overrule. Waiting for the Room to agree.
      </p>
    </div>

    <p
      :if={!(@room.overrule && @room.overrule.pending?) && @room[:overrule_declined]}
      data-role="overrule-declined"
      class="text-center text-sm opacity-80"
    >
      <span class="font-semibold">{@room[:overrule_declined][:name]}</span>
      declined. The Assayer's grade stands for this Attempt.
    </p>

    <p
      :if={@room.reveal && @room.reveal[:overruled?]}
      data-role="overruled-notice"
      class="text-center text-sm font-semibold text-primary"
    >
      Overruled jointly - recorded in the Chronicle as precedent.
    </p>
    """
  end

  # What the table is being asked to agree to. Every Overrule used to be a Meld,
  # because the proposer had no number to reach for; a Split reading hands them
  # one, and it may not be a Meld, so the banner says which it is.
  defp proposed_grade(%{closeness: closeness}) when is_integer(closeness) do
    if Thereish.Ladder.melded?(closeness), do: "a Meld", else: to_string(closeness)
  end

  defp proposed_grade(_overrule), do: "a Meld"

  attr :room, :map, required: true

  @doc """
  The shared pause after a reveal, on every screen, until anyone may advance.
  """
  def reveal_hold(assigns) do
    ~H"""
    <p
      :if={@room.phase in [:reveal, :closed] and @room[:can_advance?] == false}
      data-role="reveal-hold"
      class="text-center text-sm opacity-70"
    >
      A moment for the reveal.
    </p>
    """
  end

  attr :room, :map, required: true

  @doc """
  What a miss means, said out loud on every screen: the two Bridges that landed
  furthest apart are the next attempt's Bookends, named.

  One component rather than a line on each view, because "a miss converges" is a
  rule, and a rule said in two wordings is two rules. It names the words because
  at four Seats "those two words" points at nothing.
  """
  def carry_forward(assigns) do
    ~H"""
    <p
      :if={@room.phase == :reveal && @room.next_bookends}
      data-role="carry-forward"
      class="text-center text-sm opacity-70"
    >
      <span :if={@room[:next_bookends_chosen?] == false}>
        No verdict, so nobody chose:
      </span>
      <span class="font-semibold">{join_and(@room.next_bookends)}</span>
      become the next bookends.
    </p>
    """
  end

  attr :room, :map, required: true

  @doc """
  The end of a Page, said as an ending.

  A Page that ran out of attempts has not gone wrong, and this line is the whole
  difference between an ending and an error message: the players spent five
  tries on two words and did not converge, which is the game working.

  The closing card is also where the calibration labour lives now. The fairness
  tap and the Bookends taps used to sit under the number at the reveal, which
  put a survey about the grader in the two seconds that belong to the
  punchline; both are here, behind a Notes disclosure, so the ending line and
  the arc own the card. The rule did not move — the Game permits a tap at a
  reveal and at a close exactly as it did (ADR-0019) — only the buttons did.
  """
  attr :seat, :map, default: nil
  attr :mode, :atom, default: :phone

  def ending(assigns) do
    ~H"""
    <section
      :if={@room.closed}
      data-role="ending"
      class={[
        "flex flex-col items-center w-full",
        if(@mode == :stage, do: "gap-2 sm:gap-3", else: "gap-4")
      ]}
    >
      <p
        data-role="ending-line"
        class={[
          "max-w-prose text-center font-medium",
          if(@mode == :stage, do: "text-lg sm:text-xl", else: "text-xl")
        ]}
      >
        {ending_line(@room.closed)}
      </p>

      <ol
        :if={@room.played != []}
        data-role="arc"
        class={[
          "flex flex-col opacity-70",
          if(@mode == :stage, do: "gap-0.5 sm:gap-1 text-xs sm:text-sm", else: "gap-1 text-sm")
        ]}
      >
        <li
          :for={attempt <- @room.played}
          data-attempt={attempt.number}
          class="flex flex-wrap items-baseline justify-center gap-2"
        >
          <span>{Enum.join(attempt.bookends, " + ")}</span>
          <span aria-hidden="true">→</span>
          <span class="font-semibold">
            {attempt.bridges |> Enum.map(& &1.bridge) |> Enum.join(" · ")}
          </span>
          <span>{attempt.closeness || "no verdict"}</span>
        </li>
      </ol>

      <details
        :if={@mode == :phone && (may?(@room, :tap_fairness) || may?(@room, :tap_bookends))}
        data-role="notes"
        class="w-full max-w-sm rounded-xl border border-base-300 bg-base-100/60"
      >
        <summary class="cursor-pointer px-3 py-2 text-center text-xs font-semibold uppercase tracking-wider opacity-60">
          Notes
        </summary>
        <div class="flex flex-col items-center gap-3 px-3 pb-3">
          <.fairness_controls :if={may?(@room, :tap_fairness)} room={@room} seat={@seat} />

          <div
            :if={may?(@room, :tap_bookends)}
            data-role="bookends-controls"
            class="flex flex-col items-center gap-2 pt-2"
          >
            <span class="text-xs font-semibold uppercase tracking-wider opacity-60">
              How were these Bookends?
            </span>
            <div class="flex items-center gap-2">
              <button
                type="button"
                phx-click="bookends_tap"
                phx-value-label="flat"
                data-role="tap-flat"
                data-tap="flat"
                class={[
                  "btn btn-sm text-xs font-medium transition-all",
                  if(your_bookends_tap(@room, @seat) == "flat",
                    do: "btn-warning text-warning-content font-bold shadow-sm",
                    else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
                  )
                ]}
              >
                Flat
              </button>
              <button
                type="button"
                phx-click="bookends_tap"
                phx-value-label="fine"
                data-role="tap-fine"
                data-tap="fine"
                class={[
                  "btn btn-sm text-xs font-medium transition-all",
                  if(your_bookends_tap(@room, @seat) == "fine",
                    do: "btn-primary font-bold shadow-sm",
                    else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
                  )
                ]}
              >
                Fine
              </button>
              <button
                type="button"
                phx-click="bookends_tap"
                phx-value-label="great"
                data-role="tap-great"
                data-tap="great"
                class={[
                  "btn btn-sm text-xs font-medium transition-all",
                  if(your_bookends_tap(@room, @seat) == "great",
                    do: "btn-success text-success-content font-bold shadow-sm",
                    else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
                  )
                ]}
              >
                Great
              </button>
            </div>
            <%= if tap = your_bookends_tap(@room, @seat) do %>
              <div
                data-role="your-bookends-tap"
                class="flex items-center gap-1.5 text-xs text-primary font-medium"
              >
                <span data-role="seat-bookends-tap" class="font-semibold capitalize">
                  {tap}
                </span>
                recorded
              </div>
            <% end %>
          </div>
        </div>
      </details>
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
  Whether the Room is still between the Bookends and the reveal.

  Once the Bridges are up on the screen, who had already written one and what
  this phone wrote are answered by the reveal itself, and saying it twice makes
  the reveal read as a page still in progress.
  """
  def mid_page?(room), do: room.phase in [:bridging, :assaying]

  @doc """
  Whether the Game would take `action` from this screen's viewer right now, as
  `Thereish.Game.view/2` put it in `may`. A screen with no Room yet may do
  nothing.
  """
  def may?(room, action), do: get_in(room, [:may, action]) == true

  # The rules name a rung; nobody says "deep_meld" out loud.
  defp band(nil), do: ""
  defp band(name), do: name |> to_string() |> String.replace("_", " ")

  defp waiting_line(nil), do: "Every bridge is in. The Assayer is looking at them."
  defp waiting_line(:grading), do: waiting_line(nil)
  defp waiting_line(:slow), do: "The Assayer is still reading. It does this sometimes."
  defp waiting_line(_), do: waiting_line(nil)

  defp waiting(%{seats: [_]}), do: "Waiting for 1 more"
  defp waiting(_), do: nil

  defp reveal_arrival(%{melded?: true}), do: "meld"
  defp reveal_arrival(%{band: band}) when not is_nil(band), do: to_string(band)
  defp reveal_arrival(_), do: "no_verdict"

  # What the card the number sits in looks like. Six clauses used to give a 29
  # and a 54 the same grey, which is the whole reason the bands were invisible:
  # now the card wears the band's own `data-band` and the colour behind it is
  # the theme's token (`.band-tint` in app.css), the same token the badge and
  # the Rail read. A Meld keeps the lift that makes it an arrival.
  defp closeness_presentation(%{melded?: true}) do
    %{
      container_class: "border-2 band-tint shadow-xl shadow-primary/20",
      number_class: "text-primary",
      badge_class: "bg-primary text-primary-content font-bold"
    }
  end

  defp closeness_presentation(_reveal) do
    %{
      container_class: "border band-tint",
      number_class: "text-base-content",
      badge_class: "band-badge font-bold"
    }
  end

  # The one place the sequence's numbers live is the config Pacing reads when it
  # arms the hold: the performance is absorbed by the hold rather than added to
  # it, and two readings of that would be two answers.
  defp reveal_sequence, do: Application.fetch_env!(:thereish, :reveal_sequence_ms)

  # Calls, each wearing the colour its Seat wears everywhere else — the Beat's
  # row and the Rail's pins read the same list. The Game says who called which
  # band and nothing about how a Seat looks, so the colour is read off the
  # roster the screen already has.
  defp coloured_calls(room, calls) do
    colours = Map.new(room[:seats] || [], &{&1.id, seat_colour(&1)})

    for call <- calls || [] do
      Map.put(call, :colour, colours[call.seat_id])
    end
  end

  defp chosen_opinion_class("too_harsh"),
    do: "btn-warning text-warning-content font-bold shadow-sm"

  defp chosen_opinion_class("fair"), do: "btn-primary font-bold shadow-sm"
  defp chosen_opinion_class("too_kind"), do: "btn-info text-info-content font-bold shadow-sm"

  defp your_fairness_tap(room, seat) do
    room[:your_tap] || (room[:fairness_taps] && seat && room.fairness_taps[seat.id])
  end

  defp your_bookends_tap(room, seat) do
    room[:your_bookends_tap] ||
      (room[:bookends_taps] && seat && room.bookends_taps[seat.id])
  end

  defp you?(seat, bridge), do: seat != nil and seat.id == bridge.seat_id

  attr :state, :atom, default: :none, doc: ":self, :other, or :none"

  def speaker_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="currentColor"
      class="size-5 inline-block"
      aria-hidden="true"
    >
      <path
        :if={@state == :none}
        d="M13.5 4.06c0-1.336-1.616-2.005-2.56-1.06l-4.5 4.5H4.5A2.25 2.25 0 0 0 2.25 9.75v4.5a2.25 2.25 0 0 0 2.25 2.25h1.94l4.5 4.5c.944.945 2.56.276 2.56-1.06V4.06ZM17.78 9.22a.75.75 0 1 0-1.06 1.06L18.44 12l-1.72 1.72a.75.75 0 0 0 1.06 1.06l1.72-1.72 1.72 1.72a.75.75 0 1 0 1.06-1.06L20.56 12l1.72-1.72a.75.75 0 0 0-1.06-1.06l-1.72 1.72-1.72-1.72Z"
      />
      <path
        :if={@state == :other}
        d="M13.5 4.06c0-1.336-1.616-2.005-2.56-1.06l-4.5 4.5H4.5A2.25 2.25 0 0 0 2.25 9.75v4.5a2.25 2.25 0 0 0 2.25 2.25h1.94l4.5 4.5c.944.945 2.56.276 2.56-1.06V4.06ZM18.75 12a6.75 6.75 0 0 0-1.9-4.72.75.75 0 0 0-1.06 1.06 5.25 5.25 0 0 1 0 7.32.75.75 0 0 0 1.06 1.06A6.75 6.75 0 0 0 18.75 12Z"
      />
      <path
        :if={@state == :self}
        d="M13.5 4.06c0-1.336-1.616-2.005-2.56-1.06l-4.5 4.5H4.5A2.25 2.25 0 0 0 2.25 9.75v4.5a2.25 2.25 0 0 0 2.25 2.25h1.94l4.5 4.5c.944.945 2.56.276 2.56-1.06V4.06ZM19.11 4.89a.75.75 0 0 1 1.06 0 10.5 10.5 0 0 1 0 14.85.75.75 0 0 1-1.06-1.06 9 9 0 0 0 0-12.73.75.75 0 0 1 0-1.06ZM16.5 7.5a.75.75 0 0 1 1.06 0 6.75 6.75 0 0 1 0 9.54.75.75 0 0 1-1.06-1.06 5.25 5.25 0 0 0 0-7.42.75.75 0 0 1 0-1.06Z"
      />
    </svg>
    """
  end

  @doc """
  Per-device sound switch for local commit sounds.
  Defaults to on in browser storage, toggled by tap, persists across reload.
  When a Stage is present, commit sounds play from the Stage and the switch
  notes this honestly in its title and aria-label while preserving the device
  preference for play without a Stage.
  """
  attr :stage_present?, :boolean, default: false

  def local_sound_switch(assigns) do
    {title, aria_label} =
      if assigns.stage_present? do
        {"Commit sound plays from the Stage while connected",
         "Toggle commit sound on this device (commit sound plays from the Stage while connected)"}
      else
        {"Toggle commit sound on this device", "Toggle commit sound on this device"}
      end

    assigns =
      assigns
      |> assign(:title, title)
      |> assign(:aria_label, aria_label)

    ~H"""
    <button
      type="button"
      id="local-sound-toggle"
      phx-hook=".LocalSoundToggle"
      data-role="local-sound-toggle"
      data-sound="on"
      aria-label={@aria_label}
      title={@title}
      class="flex items-center justify-center p-1 rounded hover:bg-base-200 transition-colors opacity-70 hover:opacity-100 cursor-pointer"
    >
      <svg
        data-state="on"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 20 20"
        fill="currentColor"
        class="size-4 inline-block"
        aria-hidden="true"
      >
        <path d="M10 2a6 6 0 00-6 6v3.586l-.707.707A1 1 0 004 14h12a1 1 0 00.707-1.707L16 11.586V8a6 6 0 00-6-6zM10 18a3 3 0 01-3-3h6a3 3 0 01-3 3z" />
      </svg>
      <svg
        data-state="off"
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 20 20"
        fill="currentColor"
        class="size-4 hidden inline-block opacity-40"
        aria-hidden="true"
      >
        <path d="M3.707 2.293a1 1 0 00-1.414 1.414l14 14a1 1 0 001.414-1.414l-1.473-1.473A10.014 10.014 0 0019.542 10C18.268 5.943 14.478 3 10 3a9.958 9.958 0 00-4.512 1.074l-1.78-1.781zm4.261 4.26l1.514 1.515a2.003 2.003 0 012.45 2.45l1.514 1.514a4 4 0 00-5.478-5.478z" />
        <path d="M12.454 16.697L9.75 13.992a4 4 0 01-3.742-3.741L2.335 6.578A9.98 9.98 0 00.458 10c1.274 4.057 5.064 7 9.542 7 .847 0 1.669-.105 2.454-.303z" />
      </svg>
    </button>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalSoundToggle">
      export default {
        mounted() {
          this.syncUI = () => {
            let enabled = true
            try {
              enabled = localStorage.getItem("foley:local-sounds") !== "off"
            } catch (_) {}

            this.el.dataset.sound = enabled ? "on" : "off"
            this.el.setAttribute("aria-checked", enabled ? "true" : "false")
            const onIcon = this.el.querySelector("[data-state=on]")
            const offIcon = this.el.querySelector("[data-state=off]")
            if (onIcon && offIcon) {
              if (enabled) {
                onIcon.classList.remove("hidden")
                offIcon.classList.add("hidden")
              } else {
                onIcon.classList.add("hidden")
                offIcon.classList.remove("hidden")
              }
            }
          }

          this.syncUI()

          this.handleClick = (e) => {
            e.preventDefault()
            e.stopPropagation()
            let enabled = true
            try {
              enabled = localStorage.getItem("foley:local-sounds") !== "off"
              const next = !enabled
              localStorage.setItem("foley:local-sounds", next ? "on" : "off")
            } catch (_) {}
            this.syncUI()
          }

          this.el.addEventListener("click", this.handleClick)
        },
        updated() {
          this.syncUI()
        },
        destroyed() {
          if (this.handleClick) {
            this.el.removeEventListener("click", this.handleClick)
          }
        }
      }
    </script>
    """
  end

  attr :room, :map, required: true

  @music_options [
    {"off", "music-off", "Off"},
    {"house", "music-house", "House"},
    {"page", "music-page", "This Page"}
  ]

  def foley_switches(assigns) do
    music = to_string(assigns.room[:music] || "page")

    assigns =
      assigns
      |> assign(:current_music, music)
      |> assign(:music_options, @music_options)

    ~H"""
    <div class="flex flex-wrap items-center gap-3 text-xs opacity-80">
      <div data-role="quick-sound" class="flex flex-wrap items-center gap-3">
        <label :if={@room[:speaker?]} class="flex items-center gap-1.5 cursor-pointer">
          <input
            id="voice-switch"
            phx-hook=".VoicePref"
            type="checkbox"
            data-role="voice-switch"
            data-pref="foley:voice"
            data-default="off"
            data-kind="master"
            data-active="false"
            class="checkbox checkbox-xs"
          />
          <span>Voice</span>
        </label>
        <button
          type="button"
          data-role="settings-open"
          class="btn btn-xs btn-ghost opacity-80 hover:opacity-100"
          aria-haspopup="dialog"
          aria-controls="room-settings"
          onclick="document.getElementById('room-settings').showModal()"
        >
          Settings
        </button>
      </div>
    </div>
    <dialog id="room-settings" data-role="settings-modal" class="modal">
      <div class="modal-box max-w-sm space-y-4 text-sm">
        <h3 class="text-base font-semibold">Settings</h3>
        <div class="flex flex-col gap-2">
          <p class="text-xs uppercase tracking-wide opacity-60">Voice on this device</p>
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              id="voice-bookends-switch"
              phx-hook=".VoicePref"
              type="checkbox"
              data-role="voice-bookends-switch"
              data-pref="foley:voice-bookends"
              data-default="on"
              data-kind="bookends"
              data-active="true"
              class="checkbox checkbox-xs"
            />
            <span>Bookends</span>
          </label>
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              id="voice-verdict-switch"
              phx-hook=".VoicePref"
              type="checkbox"
              data-role="voice-verdict-switch"
              data-pref="foley:voice-verdict"
              data-default="off"
              data-kind="verdict"
              data-active="false"
              class="checkbox checkbox-xs"
            />
            <span>Verdict</span>
          </label>
        </div>
        <div class="flex flex-col gap-2">
          <p class="text-xs uppercase tracking-wide opacity-60">This device</p>
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              id="buzz-switch"
              phx-hook=".VoicePref"
              type="checkbox"
              data-role="buzz-switch"
              data-pref="juice:haptics"
              data-default="on"
              data-active="true"
              class="checkbox checkbox-xs"
            />
            <span>Buzz</span>
          </label>
        </div>
        <div class="flex flex-col gap-2">
          <p class="text-xs uppercase tracking-wide opacity-60">This Room</p>
          <label class="flex items-center gap-1.5 cursor-pointer">
            <input
              type="checkbox"
              data-role="quips-switch"
              data-active={to_string(Map.get(@room, :quips, true))}
              checked={Map.get(@room, :quips, true)}
              phx-click="toggle_quips"
              class="checkbox checkbox-xs"
            />
            <span>Quips</span>
          </label>
          <label class="flex items-start gap-1.5 cursor-pointer">
            <input
              type="checkbox"
              data-role="full-table-switch"
              data-active={to_string(Map.get(@room, :full_table, true))}
              checked={Map.get(@room, :full_table, true)}
              phx-click="toggle_full_table"
              class="checkbox checkbox-xs mt-0.5"
            />
            <span>Full table: one Bookend from every player's Give, and every Bridge carries forward</span>
          </label>
          <p
            :if={length(Map.get(@room, :seats, []) || []) == 2}
            data-role="full-table-note"
            class="opacity-70 pl-6 text-xs"
          >
            Matters from three Seats
          </p>
          <label class="flex items-start gap-1.5 cursor-pointer">
            <input
              type="checkbox"
              data-role="split-readings-switch"
              data-active={to_string(Map.get(@room, :split_readings, true))}
              checked={Map.get(@room, :split_readings, true)}
              phx-click="toggle_split_readings"
              class="checkbox checkbox-xs mt-0.5"
            />
            <span>
              Split readings: when the Assayer's two readings of the same Bridges disagree, show the table both
            </span>
          </label>
          <label class="flex items-start gap-1.5 cursor-pointer">
            <input
              type="checkbox"
              data-role="nudges-switch"
              data-active={to_string(Map.get(@room, :nudges_enabled?, true))}
              checked={Map.get(@room, :nudges_enabled?, true)}
              phx-click="toggle_nudges"
              class="checkbox checkbox-xs mt-0.5"
            />
            <span>Nudges: one word to point the table toward a meaning. Changes from the next Page.</span>
          </label>
        </div>
        <div class="flex flex-col gap-2">
          <p class="text-xs uppercase tracking-wide opacity-60">Music</p>
          <div data-role="music-control" class="join">
            <button
              :for={{mode, role, label} <- @music_options}
              type="button"
              phx-click="set_music"
              phx-value-music={mode}
              data-role={role}
              data-music={mode}
              data-active={to_string(@current_music == mode)}
              class={"btn btn-xs join-item " <> if(@current_music == mode, do: "btn-active font-semibold", else: "btn-ghost opacity-60")}
            >
              {label}
            </button>
          </div>
          <div class="flex items-center gap-2">
            <button
              :if={@room[:speaker?] and @room[:next?]}
              type="button"
              phx-click="next_music"
              data-role="music-next"
              class="btn btn-xs btn-ghost opacity-70 hover:opacity-100"
            >
              Next
            </button>
            <button
              :if={@room[:speaker?] and @room[:never?]}
              type="button"
              phx-click="never_music"
              data-role="music-never"
              class="btn btn-xs btn-ghost opacity-70 hover:opacity-100"
            >
              Never
            </button>
          </div>
        </div>
        <form method="dialog" class="modal-action">
          <button type="submit" data-role="settings-close" class="btn btn-sm">Close</button>
        </form>
      </div>
      <form method="dialog" class="modal-backdrop">
        <button type="submit">close</button>
      </form>
    </dialog>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".VoicePref">
      export default {
        mounted() {
          const key = this.el.dataset.pref
          const defaultOn = this.el.dataset.default !== "off"
          const kind = this.el.dataset.kind
          this.syncUI = () => {
            let enabled = defaultOn
            try {
              const stored = localStorage.getItem(key)
              if (stored === "on") enabled = true
              else if (stored === "off") enabled = false
            } catch (_) {}
            this.el.checked = enabled
            this.el.dataset.active = enabled ? "true" : "false"
            this.el.setAttribute("aria-checked", enabled ? "true" : "false")
          }
          this.syncUI()

          this.handleChange = () => {
            const next = !!this.el.checked
            try {
              localStorage.setItem(key, next ? "on" : "off")
            } catch (_) {}
            this.syncUI()
            // A switch with no kind is a plain device preference — the Buzz is
            // one — and has nothing to tell the Voice about.
            if (kind) {
              document.dispatchEvent(
                new CustomEvent("thereish:voice-pref", { detail: { enabled: next, kind } })
              )
            }
          }

          this.el.addEventListener("change", this.handleChange)
        },
        updated() {
          this.syncUI()
        },
        destroyed() {
          if (this.handleChange) {
            this.el.removeEventListener("change", this.handleChange)
          }
        }
      }
    </script>
    """
  end

  attr :room, :map, required: true

  def now_playing(assigns) do
    ~H"""
    <p
      :if={now_playing_text(@room)}
      data-role="now-playing"
      class="text-xs opacity-60 text-center"
    >
      {now_playing_text(@room)}
    </p>
    """
  end

  def now_playing_text(nil), do: nil

  def now_playing_text(room) do
    cond do
      to_string(room[:music]) == "off" and
          room[:phase] in [:bridging, :assaying, :reveal, :closed] ->
        "Music is off"

      room[:playing] && room.playing[:kind] in ["track", "vamp"] ->
        if room[:first_revealed?] == true and room.playing[:title] do
          "Now playing: #{room.playing.title} (written for this Page)"
        else
          "Now playing: written for this Page"
        end

      room[:playing] && room.playing[:kind] == "holdover" && room.playing[:title] ->
        "Now playing: #{room.playing.title} (last Page's Track)"

      room[:playing] && room.playing[:kind] == "repertoire" && room.playing[:title] ->
        "Now playing: #{room.playing.title} (the Repertoire)"

      true ->
        nil
    end
  end

  attr :room, :map, default: nil
  attr :floats, :boolean, default: false, doc: "whether reactions lift off the Seats' Masks"

  @doc """
  Juice: the buzz in the hand, and the reactions lifting off the Stage.

  Both read the same diff the sound does — one buzz per Cue the Room pushed,
  one float per Reaction that is new since the last render — so a phone that
  slept and came back does not replay the night at its owner. Nothing here is
  counted or kept.
  """
  def juice_hook(assigns) do
    assigns =
      assigns
      |> assign(:signature, reaction_signature(assigns.room))
      |> assign(:attempt, assigns.room && get_in(assigns.room, [:attempt, :number]))

    ~H"""
    <div
      id="juice-container"
      phx-hook=".Juice"
      data-floats={to_string(@floats)}
      data-attempt={@attempt}
      data-reactions={@signature}
      class="hidden"
    >
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Juice">
      export default {
        mounted() {
          // What this device has already answered for. A Stage or a phone that
          // arrives mid-reveal records what is there and floats none of it,
          // the same rule the Cues keep for a screen's first render.
          this.floated = new Map()
          this.attempt = this.el.dataset.attempt

          this.reduced = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches
          this.buzzOn = () => {
            try {
              return localStorage.getItem("juice:haptics") !== "off"
            } catch (_) {
              return true
            }
          }

          // Feature detection and nothing more: a laptop and an iPhone have no
          // vibrator, so the buzz is a silent no-op there. The device this is
          // for is the phone in a hand.
          this.handleEvent("juice:haptic", ({pattern}) => {
            if (!navigator.vibrate || !Array.isArray(pattern) || !this.buzzOn()) return
            try {
              navigator.vibrate(pattern)
            } catch (_) {}
          })

          this.sync(true)
        },

        updated() {
          this.sync(false)
        },

        sync(first) {
          if (this.el.dataset.attempt !== this.attempt) {
            this.attempt = this.el.dataset.attempt
            this.floated = new Map()
          }

          const pairs = (this.el.dataset.reactions || "")
            .split(" ")
            .filter(Boolean)
            .map((pair) => pair.split(":"))

          pairs.forEach(([seat, reaction], i) => {
            if (this.floated.get(seat) === reaction) return
            this.floated.set(seat, reaction)
            if (first || this.el.dataset.floats !== "true") return
            this.float(seat, reaction, i)
          })
        },

        // The word lifts off whoever shouted it: their Mask on the Stage, and
        // their own Bridge card once the Masks have gone.
        float(seat, reaction, i) {
          const anchor =
            document.querySelector('[data-role="stage-mask"][data-seat="' + CSS.escape(seat) + '"]') ||
            document.querySelector('[data-bridge="' + CSS.escape(seat) + '"]')
          if (!anchor) return

          const box = anchor.getBoundingClientRect()
          const node = document.createElement("div")
          node.dataset.role = "reaction-float"
          node.textContent = reaction.replace(/_/g, " ").toUpperCase()
          node.style.cssText =
            "position:fixed;z-index:60;pointer-events:none;white-space:nowrap;" +
            "font-weight:800;letter-spacing:0.15em;font-size:1.5rem;" +
            "left:" + (box.left + box.width / 2) + "px;top:" + box.top + "px;" +
            "transform:translate(-50%, 0);"
          document.body.appendChild(node)

          if (this.reduced()) {
            setTimeout(() => node.remove(), 1200)
            return
          }

          const anim = node.animate(
            [
              {opacity: 1, transform: "translate(-50%, 0)"},
              {opacity: 0, transform: "translate(-50%, -80px)"}
            ],
            {duration: 1600, delay: i * 120, easing: "cubic-bezier(.16,1,.3,1)", fill: "backwards"}
          )
          anim.onfinish = () => node.remove()
          anim.oncancel = () => node.remove()
        }
      }
    </script>
    """
  end

  # The Reactions as the hook reads them: one `seat:word` pair per Seat, which
  # is a list of who shouted what and never a tally of how many did.
  defp reaction_signature(nil), do: nil

  defp reaction_signature(room) do
    case room[:reactions] || [] do
      [] -> nil
      reactions -> Enum.map_join(reactions, " ", &"#{&1.seat_id}:#{&1.reaction}")
    end
  end

  attr :speaker, :boolean, default: false
  attr :levels, :list, default: nil
  attr :meld_cue_delay_ms, :integer, default: nil

  def foley_hook(assigns) do
    levels = assigns[:levels] || Thereish.Steward.foley_levels()

    meld_cue_delay_ms =
      assigns[:meld_cue_delay_ms] || Thereish.Steward.foley_meld_cue_delay_ms()

    assigns = assigns |> assign(:levels, levels) |> assign(:meld_cue_delay_ms, meld_cue_delay_ms)

    ~H"""
    <div
      id="foley-container"
      phx-hook=".Foley"
      data-speaker={to_string(@speaker)}
      data-mode={if @speaker, do: "speaker", else: "local"}
      data-level-music={to_string(@levels[:music] || 0.5)}
      data-level-stings={to_string(@levels[:stings] || 1.2)}
      data-level-voice={to_string(@levels[:voice] || 1.2)}
      data-level-duck={to_string(@levels[:duck] || 0.15)}
      data-level-duck-stings={to_string(@levels[:duck_stings] || 0.35)}
      data-meld-cue-delay-ms={to_string(@meld_cue_delay_ms)}
      class="hidden"
    >
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Foley">
      export default {
        mounted() {
          this.speaker = this.el.dataset.speaker === "true"
          this.mode = this.el.dataset.mode || (this.speaker ? "speaker" : "local")
          // Read the speaker off the DOM rather than off the last `updated()`:
          // the tap that claims the Speaker is answered with the patch and the
          // first `foley:page` together, and a stale flag would swallow it.
          //
          // Sound is the Speaker's business and nothing else's. This used to
          // ask about reduced motion too, which silenced the music, the stings
          // and every voice for anyone who had asked only for less movement —
          // the richest part of the night, taken away by a motion setting.
          this.canPlay = () => this.el.dataset.speaker === "true"
          this.ctx = null
          this.musicBus = null
          this.stingsBus = null
          this.voiceBus = null
          this.musicSource = null
          this.voiceSource = null
          this.voiceObserver = null
          this.currentVoiceAttempt = null
          this.currentVoiceKind = null
          this.latestVoiceAttempt = null
          this.musicOff = false
          this.audioBuffers = new Map()

          this.storedPref = (key, defaultOn) => {
            try {
              const stored = localStorage.getItem(key)
              if (stored === "on") return true
              if (stored === "off") return false
            } catch (_) {}
            return defaultOn
          }
          this.voiceMasterOn = () => this.storedPref("foley:voice", false)
          this.bookendsOn = () => this.voiceMasterOn() && this.storedPref("foley:voice-bookends", true)
          this.verdictOn = () => this.voiceMasterOn() && this.storedPref("foley:voice-verdict", false)
          this.clearVoice = () => {
            this.stopVoice()
            this.currentVoiceAttempt = null
            this.currentVoiceKind = null
          }
          this.onVoicePref = (e) => {
            const detail = (e && e.detail) || {}
            if (detail.enabled !== false) return
            if (!detail.kind || detail.kind === "master" || detail.kind === this.currentVoiceKind) {
              this.clearVoice()
            }
          }
          document.addEventListener("thereish:voice-pref", this.onVoicePref)

          const parseLevel = (val, fallback) => {
            const parsed = parseFloat(val)
            return isNaN(parsed) ? fallback : parsed
          }
          this.levels = {
            music: parseLevel(this.el.dataset.levelMusic, 0.5),
            stings: parseLevel(this.el.dataset.levelStings, 1.2),
            voice: parseLevel(this.el.dataset.levelVoice, 1.2),
            duck: parseLevel(this.el.dataset.levelDuck, 0.15),
            duckStings: parseLevel(this.el.dataset.levelDuckStings, 0.35)
          }

          this.parseDelay = (val, fallback) => {
            const parsed = parseInt(val, 10)
            return isNaN(parsed) ? fallback : parsed
          }
          this.meldCueDelayMs = this.parseDelay(this.el.dataset.meldCueDelayMs, 1800)
          this.endingTimeout = null
          this.clearEndingTimeout = () => {
            if (this.endingTimeout) {
              clearTimeout(this.endingTimeout)
              this.endingTimeout = null
            }
          }

          this.initAudio = () => {
            if (this.ctx) return
            const AudioContext = window.AudioContext || window.webkitAudioContext
            if (!AudioContext) return
            this.ctx = new AudioContext()

            this.musicBus = this.ctx.createGain()
            this.stingsBus = this.ctx.createGain()
            this.voiceBus = this.ctx.createGain()

            this.musicBus.gain.setValueAtTime(this.levels.music, this.ctx.currentTime)
            this.stingsBus.gain.setValueAtTime(this.levels.stings, this.ctx.currentTime)
            this.voiceBus.gain.setValueAtTime(this.levels.voice, this.ctx.currentTime)

            this.musicBus.connect(this.ctx.destination)
            this.stingsBus.connect(this.ctx.destination)
            this.voiceBus.connect(this.ctx.destination)
          }

          this.resumeAudio = async () => {
            this.initAudio()
            if (this.ctx && this.ctx.state !== "running") {
              await this.ctx.resume()
            }
          }

          // The tap and the speaker toggle are rendered by the view, so they
          // come and go and move between the header and the waiting screen.
          // One delegated listener outlives all of that.
          this.onTapClick = (e) => {
            if (e.target && e.target.closest("#tap-for-sound, [data-role=speaker-toggle]")) {
              this.resumeAudio()
            }
          }
          document.addEventListener("click", this.onTapClick)

          this.onFormSubmit = (e) => {
            if (e.target && (e.target.id === "bridge-form" || e.target.closest("#bridge-form"))) {
              this.resumeAudio()
            }
          }

          this.onCommitClick = (e) => {
            if (e.target && e.target.closest("#bridge-form button, [phx-submit=commit_bridge] button")) {
              this.resumeAudio()
            }
          }

          document.addEventListener("submit", this.onFormSubmit)
          document.addEventListener("click", this.onCommitClick)

          this.fetchBuffer = async (url) => {
            if (this.audioBuffers.has(url)) return this.audioBuffers.get(url)
            try {
              const res = await fetch(url)
              if (!res.ok) return null
              const arrayBuf = await res.arrayBuffer()
              const audioBuf = await this.ctx.decodeAudioData(arrayBuf)
              this.audioBuffers.set(url, audioBuf)
              return audioBuf
            } catch (err) {
              return null
            }
          }

          this.duckMusic = (durationSeconds = 2.0) => {
            if (!this.ctx || !this.musicBus || this.musicOff) return
            const now = this.ctx.currentTime
            this.duckUntil = Math.max(this.duckUntil || 0, now + durationSeconds)
            this.musicBus.gain.cancelScheduledValues(now)
            this.musicBus.gain.setTargetAtTime(this.levels.duck, now, 0.05)
            this.musicBus.gain.setTargetAtTime(this.levels.music, this.duckUntil, 0.2)
          }

          this.restoreMusic = () => {
            if (!this.ctx || !this.musicBus || this.musicOff) return
            const now = this.ctx.currentTime
            this.duckUntil = 0
            this.musicBus.gain.cancelScheduledValues(now)
            this.musicBus.gain.setTargetAtTime(this.levels.music, now, 0.1)
          }

          this.isDucked = () => {
            return !this.musicOff && Boolean(this.duckUntil && this.ctx && this.ctx.currentTime < this.duckUntil)
          }

          this.duckStings = (durationSeconds = 2.0) => {
            if (!this.ctx || !this.stingsBus) return
            const now = this.ctx.currentTime
            this.stingsDuckUntil = Math.max(this.stingsDuckUntil || 0, now + durationSeconds)
            this.stingsBus.gain.cancelScheduledValues(now)
            this.stingsBus.gain.setTargetAtTime(this.levels.duckStings, now, 0.05)
            this.stingsBus.gain.setTargetAtTime(this.levels.stings, this.stingsDuckUntil, 0.2)
          }

          this.restoreStings = () => {
            if (!this.ctx || !this.stingsBus) return
            const now = this.ctx.currentTime
            this.stingsDuckUntil = 0
            this.stingsBus.gain.cancelScheduledValues(now)
            this.stingsBus.gain.setTargetAtTime(this.levels.stings, now, 0.1)
          }

          this.isStingsDucked = () => {
            return Boolean(this.stingsDuckUntil && this.ctx && this.ctx.currentTime < this.stingsDuckUntil)
          }

          this.stopVoice = () => {
            if (this.voiceObserver) {
              this.voiceObserver.disconnect()
              this.voiceObserver = null
            }
            if (this.voiceSource) {
              try { this.voiceSource.stop() } catch (_) {}
              this.voiceSource = null
              this.restoreMusic()
              this.restoreStings()
            }
          }

          this.playEffect = async (url, bus, duckDuration = 2.0) => {
            if (!this.canPlay()) return
            await this.resumeAudio()
            if (!this.ctx) return
            const buf = await this.fetchBuffer(url)
            if (!buf) return
            const source = this.ctx.createBufferSource()
            source.buffer = buf
            source.connect(bus)
            if (duckDuration > 0) {
              this.duckMusic(duckDuration)
            }
            source.start(0)
          }

          this.fadeMusicOut = (fadeDuration = 2.0) => {
            if (!this.ctx || !this.musicBus) return
            const now = this.ctx.currentTime
            this.duckUntil = 0
            this.musicBus.gain.cancelScheduledValues(now)
            this.musicBus.gain.setValueAtTime(this.musicBus.gain.value, now)
            this.musicBus.gain.linearRampToValueAtTime(0.001, now + fadeDuration)
            const oldMusic = this.currentMusic
            this.currentMusic = null
            this.musicSource = null
            if (oldMusic) {
              setTimeout(() => {
                try {
                  if (oldMusic.source && oldMusic.source.stop) oldMusic.source.stop()
                } catch (_) {}
              }, fadeDuration * 1000 + 100)
            }
          }

          this.stopMusic = () => {
            if (this.currentMusic) {
              try {
                if (this.currentMusic.source && this.currentMusic.source.stop) this.currentMusic.source.stop()
              } catch (_) {}
              this.currentMusic = null
            }
            if (this.musicSource) {
              try { this.musicSource.stop() } catch (_) {}
              this.musicSource = null
            }
          }

          this.handleEvent("foley:page", async ({path, title, kind}) => {
            if (!this.canPlay()) return
            await this.resumeAudio()
            if (!this.ctx) return

            const now = this.ctx.currentTime
            const fadeDuration = 2.0

            if (!path) {
              this.musicOff = true
              this.fadeMusicOut(fadeDuration)
              return
            }

            this.musicOff = false

            const trackUrl = path

            if (this.currentMusic && this.currentMusic.path === trackUrl) {
              const targetGain = this.isDucked() ? this.levels.duck : this.levels.music
              this.musicBus.gain.cancelScheduledValues(now)
              this.musicBus.gain.setValueAtTime(this.musicBus.gain.value, now)
              this.musicBus.gain.linearRampToValueAtTime(targetGain, now + 1.0)
              if (this.isDucked() && this.duckUntil > now) {
                this.musicBus.gain.setTargetAtTime(this.levels.music, this.duckUntil, 0.2)
              }
              return
            }

            const buf = await this.fetchBuffer(trackUrl)
            if (!buf) return

            if (this.currentMusic && this.currentMusic.path === trackUrl) {
              return
            }

            const playNow = this.ctx.currentTime

            const newSource = this.ctx.createBufferSource()
            newSource.buffer = buf
            newSource.loop = true

            const newGain = this.ctx.createGain()
            newSource.connect(newGain)
            newGain.connect(this.musicBus)

            const targetGain = this.isDucked() ? this.levels.duck : this.levels.music
            this.musicBus.gain.cancelScheduledValues(playNow)
            this.musicBus.gain.setValueAtTime(this.musicBus.gain.value, playNow)
            this.musicBus.gain.linearRampToValueAtTime(targetGain, playNow + fadeDuration)
            if (this.isDucked() && this.duckUntil > playNow) {
              this.musicBus.gain.setTargetAtTime(this.levels.music, this.duckUntil, 0.2)
            }

            const oldMusic = this.currentMusic
            if (oldMusic) {
              newGain.gain.setValueAtTime(0.001, playNow)
              newGain.gain.linearRampToValueAtTime(1.0, playNow + fadeDuration)

              oldMusic.gain.gain.cancelScheduledValues(playNow)
              oldMusic.gain.gain.setValueAtTime(oldMusic.gain.gain.value, playNow)
              oldMusic.gain.gain.linearRampToValueAtTime(0.001, playNow + fadeDuration)
              setTimeout(() => {
                try {
                  if (oldMusic.source && oldMusic.source.stop) oldMusic.source.stop()
                } catch (_) {}
              }, fadeDuration * 1000 + 100)
            } else {
              newGain.gain.setValueAtTime(1.0, now)
            }

            newSource.start(0)

            this.currentMusic = {source: newSource, gain: newGain, path: trackUrl, title: title, kind: kind}
            this.musicSource = newSource
          })

          this.handleEvent("foley:beat", async () => {
            this.clearVoice()
            this.playEffect("/audio/beat.mp3", this.stingsBus, 2.5)
          })

          this.handleEvent("foley:sting", async ({band}) => {
            const bandName = (band || "miss").toString().replace("_", "-")
            this.playEffect(`/audio/sting-${bandName}.mp3`, this.stingsBus, 2.0)
          })

          this.playVoiceBuffer = (buf, duckStings = true) => {
            this.stopVoice()
            const source = this.ctx.createBufferSource()
            source.buffer = buf
            source.connect(this.voiceBus)
            this.voiceSource = source

            const duration = buf.duration || 3.0
            this.duckMusic(duration)
            if (duckStings) this.duckStings(duration)

            source.onended = () => {
              if (this.voiceSource === source) {
                this.voiceSource = null
                this.restoreMusic()
                if (duckStings) this.restoreStings()
              }
            }
            source.start(0)
          }

          this.handleEvent("foley:voice", async ({url, attempt, kind}) => {
            if (!this.canPlay()) return
            if (this.latestVoiceAttempt != null && attempt < this.latestVoiceAttempt) return
            const voiceKind = kind || "verdict"
            const allowed = voiceKind === "bookends" ? this.bookendsOn() : this.verdictOn()
            if (!allowed) return

            await this.resumeAudio()
            if (!this.ctx) return

            this.stopVoice()
            this.currentVoiceAttempt = attempt
            this.currentVoiceKind = voiceKind
            this.latestVoiceAttempt = attempt

            const stillCurrent = () =>
              this.currentVoiceAttempt === attempt && this.currentVoiceKind === voiceKind

            if (voiceKind === "bookends") {
              const buf = await this.fetchBuffer(url)
              if (!buf || !this.ctx || !stillCurrent()) return
              this.playVoiceBuffer(buf, false)
              return
            }

            const isRevealReady = () =>
              document.querySelector("[data-role=quip]") ||
              document.querySelector("[data-role=fairness-controls]") ||
              document.querySelector("[data-role=closeness-display]") ||
              document.querySelector("[data-role=no-verdict]")

            const playWhenReady = (buf) => {
              if (!buf || !this.ctx || !stillCurrent()) return
              if (!isRevealReady()) return
              this.playVoiceBuffer(buf, true)
            }

            const bufPromise = this.fetchBuffer(url)

            if (isRevealReady()) {
              const buf = await bufPromise
              playWhenReady(buf)
            } else {
              const observer = new MutationObserver(async (_mutations, obs) => {
                if (!stillCurrent()) {
                  obs.disconnect()
                  if (this.voiceObserver === obs) this.voiceObserver = null
                  return
                }
                if (isRevealReady()) {
                  obs.disconnect()
                  if (this.voiceObserver === obs) this.voiceObserver = null
                  const buf = await bufPromise
                  playWhenReady(buf)
                }
              })
              this.voiceObserver = observer
              observer.observe(document.body, { childList: true, subtree: true })

              setTimeout(() => {
                if (this.voiceObserver === observer) {
                  observer.disconnect()
                  this.voiceObserver = null
                }
              }, 15000)
            }
          })

          this.handleEvent("foley:stop_voice", (payload = {}) => {
            this.clearVoice()
            if (payload.attempt != null) this.latestVoiceAttempt = payload.attempt
          })

          this.handleEvent("foley:prologue", async ({path}) => {
            if (!this.canPlay()) return
            let voiceEnabled = false
            try {
              voiceEnabled = localStorage.getItem("foley:voice") === "on"
            } catch (_) {}
            if (!voiceEnabled) return

            await this.resumeAudio()
            if (!this.ctx) return

            const buf = await this.fetchBuffer(path)
            if (!buf) return

            this.playVoiceBuffer(buf, false)
          })

          this.handleEvent("foley:stop_prologue", async () => {
            this.stopVoice()
          })

          this.playCommitTick = async () => {
            // A device whose sound has never been opened by a gesture attempts
            // nothing: an untapped Stage stays silent rather than reaching for
            // an audio context the browser will only suspend.
            if (!this.ctx) return
            await this.resumeAudio()
            if (!this.ctx) return
            const buf = await this.fetchBuffer("/audio/commit-tick.mp3")
            if (!buf) return
            const source = this.ctx.createBufferSource()
            source.buffer = buf
            source.connect(this.stingsBus || this.ctx.destination)
            source.start(0)
          }

          this.handleEvent("foley:commit", async () => {
            await this.playCommitTick()
          })

          this.handleEvent("foley:own-commit", async () => {
            let enabled = true
            try {
              enabled = localStorage.getItem("foley:local-sounds") !== "off"
            } catch (_) {}
            if (!enabled) return
            await this.playCommitTick()
          })

          this.handleEvent("foley:ending", async ({kind}) => {
            this.clearEndingTimeout()

            if (kind === "meld" || kind === "deep_meld") {
              const cueUrl = (kind === "deep_meld")
                ? "/audio/victory-deep-meld.mp3"
                : "/audio/victory-meld.mp3"
              const delayMs = this.meldCueDelayMs

              // Prefetch buffer during the delay so playback starts instantly when the timer fires
              this.fetchBuffer(cueUrl)

              this.endingTimeout = setTimeout(() => {
                this.playEffect(cueUrl, this.stingsBus, 0)
                this.fadeMusicOut(2.0)
                this.endingTimeout = null
              }, delayMs)
            } else {
              this.playEffect("/audio/ending-unmelded.mp3", this.stingsBus, 0)
              this.stopMusic()
            }
          })

          this.handleEvent("foley:stop", () => {
            this.clearEndingTimeout()
            this.clearVoice()
            this.stopMusic()
          })
        },

        updated() {
          this.speaker = this.el.dataset.speaker === "true"
          this.meldCueDelayMs = (this.parseDelay || parseInt)(this.el.dataset.meldCueDelayMs, 1800)
          this.mode = this.el.dataset.mode || (this.speaker ? "speaker" : "local")
          if (!this.speaker) {
            if (this.clearEndingTimeout) this.clearEndingTimeout()
            this.clearVoice()
            this.stopMusic()
          }
        },

        destroyed() {
          if (this.clearEndingTimeout) this.clearEndingTimeout()
          if (this.onFormSubmit) document.removeEventListener("submit", this.onFormSubmit)
          if (this.onCommitClick) document.removeEventListener("click", this.onCommitClick)
          if (this.onTapClick) document.removeEventListener("click", this.onTapClick)
          if (this.onVoicePref) document.removeEventListener("thereish:voice-pref", this.onVoicePref)
          this.clearVoice()
          this.stopMusic()
          if (this.ctx) {
            try { this.ctx.close() } catch (_) {}
            this.ctx = null
          }
        }
      }
    </script>
    """
  end
end
