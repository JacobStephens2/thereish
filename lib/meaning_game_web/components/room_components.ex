defmodule MeaningGameWeb.RoomComponents do
  @moduledoc """
  The parts of a Room that both the phones and the stage draw.

  Each of these is one component on purpose: "the stage lists who has joined;
  phones show the same roster" is a rule, and a rule with two implementations is
  a rule with two answers. The same goes for the Bookends and, most of all, for
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
          data-couple={to_string(seat.couple?)}
          class="flex items-center gap-2 text-lg"
        >
          <span class="size-2 rounded-full bg-primary" aria-hidden="true"></span>
          <span>{seat.name}</span>
          <span
            :if={seat.couple? && seat.partner_name}
            data-role="partner"
            class="text-sm opacity-70"
          >
            (with {seat.partner_name})
          </span>
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
  def bookends(assigns) do
    ~H"""
    <div :if={@room.bookends} class="flex flex-col items-center gap-3">
      <div
        data-role="bookends"
        class="flex flex-wrap items-center justify-center gap-4"
      >
        <span
          :for={bookend <- @room.bookends}
          class="rounded-lg bg-base-200 px-5 py-3 text-3xl font-semibold tracking-tight"
        >
          {bookend}
        </span>
      </div>
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
        else: "The Author is reading your settings..."}
    </p>
    """
  end

  attr :room, :map, required: true

  @doc """
  The pause while the Assayer reads the Bridges.

  Shown when the Room has moved into `:assaying` — which means every Bridge has
  been committed and the beat is running.
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
        :if={is_nil(@room.assayer_step) or @room.assayer_step == :grading}
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

      <p class="text-lg opacity-70">
        {waiting_line(@room.assayer_step)}
      </p>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :seat, :map, default: nil
  attr :mode, :atom, default: :phone

  @doc """
  The reveal: the Bridges side by side, then the number climbing into its band,
  then the punchline quip.
  """
  def reveal(assigns) do
    presentation = assigns.room.reveal && closeness_presentation(assigns.room.reveal)
    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <section
      :if={@room.reveal}
      id="reveal-performance"
      data-role="reveal"
      data-arrival={reveal_arrival(@room.reveal)}
      data-mode={@mode}
      class="flex flex-col items-center gap-8 w-full max-w-xl mx-auto"
    >
      <div
        data-role="comparison"
        style="animation: reveal-comparison 0.35s ease-out both;"
        class="flex flex-wrap items-stretch justify-center gap-3 sm:gap-4 w-full"
      >
        <div
          :for={bridge <- @room.reveal.bridges}
          data-bridge={bridge.seat_id}
          data-you={to_string(you?(@seat, bridge))}
          class={[
            "flex flex-1 min-w-[120px] sm:min-w-44 flex-col items-center justify-center gap-1 rounded-xl border p-4 text-center transition-all duration-300",
            if(you?(@seat, bridge),
              do: "border-primary/60 bg-primary/5 ring-2 ring-primary/20",
              else: "border-base-300 bg-base-100 shadow-sm"
            )
          ]}
        >
          <div class="flex items-center gap-1.5 text-xs uppercase tracking-wider opacity-60">
            <span>{bridge.name}</span>
            <span :if={you?(@seat, bridge)} class="font-bold text-primary">(you)</span>
          </div>
          <span class={[
            "font-bold tracking-tight",
            if(@mode == :stage, do: "text-3xl sm:text-4xl", else: "text-2xl sm:text-3xl")
          ]}>
            {bridge.bridge}
          </span>
        </div>
      </div>

      <% own_couple = find_own_couple(@room.reveal[:pairs], @seat) %>
      <div
        :if={@mode in [:phone, :quiet] && own_couple}
        data-role="own-couple-pair"
        class="flex flex-col items-center gap-1 rounded-xl border border-primary/40 bg-primary/10 p-4 text-center w-full max-w-sm"
      >
        <span class="text-xs uppercase tracking-widest font-semibold text-primary">
          Your couple: {Enum.join(own_couple.names, " & ")}
        </span>
        <div class="flex items-center gap-3">
          <span data-role="couple-closeness" class="text-3xl font-black tabular-nums">
            {own_couple.closeness}
          </span>
          <span class="text-sm font-bold uppercase tracking-wider opacity-80">
            {band(own_couple.band)}
          </span>
        </div>
      </div>

      <div
        :for={p <- @room.reveal[:pairs] || []}
        :if={@mode in [:phone, :quiet] && p.cross_couple_meld?}
        data-role="cross-couple-meld"
        class="alert alert-info shadow-sm text-center py-2 px-4 max-w-md w-full"
      >
        <span class="font-medium">✨ {p.surprise}</span>
      </div>

      <div
        :if={@mode != :quiet && @room.reveal.closeness}
        data-role="closeness-display"
        style="animation: reveal-closeness 0.5s cubic-bezier(0.16, 1, 0.3, 1) 0.35s both;"
        class={[
          "flex flex-col items-center justify-center rounded-2xl px-8 py-6 transition-all duration-500 w-full max-w-sm text-center",
          @presentation.container_class
        ]}
      >
        <span
          id="reveal-closeness"
          phx-hook=".ClimbNumber"
          data-role="closeness"
          data-target={@room.reveal.closeness}
          class={[
            "font-black tracking-tighter tabular-nums leading-none select-none",
            if(@mode == :stage, do: "text-9xl sm:text-[10rem]", else: "text-7xl sm:text-8xl"),
            @presentation.number_class
          ]}
        >
          {@room.reveal.closeness}
        </span>

        <div class="mt-3 flex flex-col items-center gap-1.5">
          <span
            data-role="band"
            style="animation: band-arrive 0.4s ease-out 0.8s both;"
            class={[
              "text-lg sm:text-xl font-extrabold uppercase tracking-widest px-4 py-1 rounded-full",
              @presentation.badge_class
            ]}
          >
            {band(@room.reveal.band)}
          </span>
        </div>
      </div>

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
        :if={@mode != :quiet && @room.reveal.quip}
        data-role="quip"
        class={[
          "font-serif italic font-medium leading-snug max-w-prose text-center",
          if(@mode == :stage,
            do: "text-3xl sm:text-4xl text-base-content",
            else: "text-xl sm:text-2xl text-base-content/90"
          )
        ]}
      >
        {@room.reveal.quip}
      </p>

      <div
        :if={@mode in [:phone, :quiet] && @seat && @room.reveal.closeness}
        data-role="fairness-controls"
        class="flex flex-col items-center gap-2 pt-2"
      >
        <span class="text-xs font-semibold uppercase tracking-wider opacity-60">
          Was this grade fair?
        </span>
        <div class="flex items-center gap-2">
          <button
            type="button"
            phx-click="fairness_tap"
            phx-value-label="too_harsh"
            data-role="tap-too-harsh"
            data-tap="too_harsh"
            class={[
              "btn btn-sm text-xs font-medium transition-all",
              if(your_fairness_tap(@room, @seat) == "too_harsh",
                do: "btn-warning text-warning-content font-bold shadow-sm",
                else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
              )
            ]}
          >
            Too harsh
          </button>
          <button
            type="button"
            phx-click="fairness_tap"
            phx-value-label="fair"
            data-role="tap-fair"
            data-tap="fair"
            class={[
              "btn btn-sm text-xs font-medium transition-all",
              if(your_fairness_tap(@room, @seat) == "fair",
                do: "btn-primary font-bold shadow-sm",
                else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
              )
            ]}
          >
            Fair
          </button>
          <button
            type="button"
            phx-click="fairness_tap"
            phx-value-label="too_kind"
            data-role="tap-too-kind"
            data-tap="too_kind"
            class={[
              "btn btn-sm text-xs font-medium transition-all",
              if(your_fairness_tap(@room, @seat) == "too_kind",
                do: "btn-info text-info-content font-bold shadow-sm",
                else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
              )
            ]}
          >
            Too kind
          </button>
        </div>
        <%= if tap = your_fairness_tap(@room, @seat) do %>
          <div data-role="your-tap" class="flex items-center gap-1.5 text-xs text-primary font-medium">
            <span data-role="seat-tap" class="font-semibold capitalize">
              {MeaningGame.Chronicle.FairnessTap.label_human(tap)}
            </span>
            recorded
          </div>
        <% end %>
      </div>

      <section
        :if={@mode == :stage && @room.reveal[:pairs]}
        data-role="meld-map"
        class="flex flex-col gap-5 w-full"
      >
        <div class="flex items-center justify-between border-b border-base-300 pb-2">
          <div class="flex items-center gap-2">
            <span class="size-2 rounded-full bg-primary" aria-hidden="true"></span>
            <h3 class="text-sm font-semibold uppercase tracking-widest opacity-80">Meld Map</h3>
          </div>
          <span class="text-xs opacity-50">{length(@room.reveal.pairs)} pairs</span>
        </div>

        <div
          :for={p <- @room.reveal.pairs}
          :if={p.cross_couple_meld?}
          data-role="cross-couple-meld"
          class="alert alert-info shadow-sm text-center py-2.5 px-4 rounded-xl border border-info/40 bg-info/10"
        >
          <span class="font-semibold text-lg">✨ {p.surprise}</span>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3.5">
          <div
            :for={pair <- @room.reveal.pairs}
            data-role="pair-card"
            data-couple={to_string(pair.couple?)}
            data-cross-couple-meld={to_string(pair.cross_couple_meld?)}
            class={[
              "relative flex flex-col gap-2 rounded-xl border p-4 transition-all duration-300 shadow-sm",
              if(pair.couple?,
                do: "border-primary/60 bg-primary/5 ring-1 ring-primary/30",
                else: "border-base-300 bg-base-100"
              ),
              if(pair.cross_couple_meld?, do: "ring-2 ring-info border-info/50 bg-info/5", else: "")
            ]}
          >
            <div class="flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="font-bold text-base">{Enum.join(pair.names, " ⟷ ")}</span>
              </div>
              <div class="flex items-center gap-1.5">
                <span
                  :if={pair.couple?}
                  data-role="couple-badge"
                  class="badge badge-primary badge-sm font-bold uppercase tracking-wider text-[10px]"
                >
                  Couple
                </span>
                <span
                  :if={pair.melded?}
                  data-role="meld-badge"
                  class="badge badge-success badge-sm font-bold uppercase tracking-wider text-[10px]"
                >
                  Meld
                </span>
              </div>
            </div>

            <div class="flex items-center justify-between text-sm pt-1 border-t border-base-200">
              <span class="opacity-75 font-serif italic text-base">
                "{hd(pair.bridges)}" ··· "{List.last(pair.bridges)}"
              </span>
              <div class="flex items-center gap-1.5">
                <span class="font-mono font-black text-lg">{pair.closeness}</span>
                <span class="text-xs uppercase font-bold tracking-wider opacity-70">
                  ({band(pair.band)})
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      <p :if={@mode == :stage} class="text-xs font-semibold uppercase tracking-widest opacity-50">
        The couch has the call · Use your phones to continue or overrule
      </p>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ClimbNumber">
        export default {
          mounted() {
            const target = parseInt(this.el.dataset.target, 10)
            if (isNaN(target)) return
            if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
              this.el.textContent = target
              return
            }
            const delay = 350
            const duration = 650
            let started = false
            let startTime = null
            this.el.textContent = "0"

            const tick = (now) => {
              if (!started) {
                startTime = now + delay
                started = true
              }
              if (now < startTime) {
                requestAnimationFrame(tick)
                return
              }
              const elapsed = now - startTime
              const progress = Math.min(elapsed / duration, 1)
              const ease = 1 - Math.pow(1 - progress, 3)
              const current = Math.round(ease * target)
              this.el.textContent = current
              if (progress < 1) {
                requestAnimationFrame(tick)
              } else {
                this.el.textContent = target
              }
            }
            requestAnimationFrame(tick)
          }
        }
      </script>
    </section>
    """
  end

  attr :room, :map, required: true
  attr :seat, :map, default: nil

  @doc """
  The overrule banner: visible on both phones and the stage while a proposal is
  pending, and showing the joint ruling once agreed.
  """
  def overrule_banner(assigns) do
    ~H"""
    <div
      :if={@room.overrule && @room.overrule.pending?}
      data-role="overrule-banner"
      class="flex flex-col items-center gap-2 rounded-lg border border-primary/30 bg-base-200/50 p-4 text-center"
    >
      <p :if={@seat && @room.overrule.you_proposed?} data-role="overrule-pending">
        You proposed an overrule. Waiting for everyone to agree.
      </p>

      <div
        :if={@seat && !@room.overrule.you_agreed?}
        data-role="overrule-vote"
        class="flex flex-col items-center gap-3"
      >
        <p data-role="overrule-pending">
          <span class="font-semibold">{@room.overrule.proposer_name}</span>
          proposed overruling this grade to a Meld.
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
        :if={@seat && @room.overrule.you_agreed? && !@room.overrule.you_proposed?}
        data-role="overrule-pending"
      >
        You agreed. Waiting for everyone to agree.
      </p>

      <p :if={is_nil(@seat)} data-role="overrule-pending" class="opacity-80">
        <span class="font-semibold">{@room.overrule.proposer_name}</span>
        proposed an overrule. Waiting for the Room to agree.
      </p>
    </div>

    <p
      :if={@room.reveal && @room.reveal.overruled?}
      data-role="overruled-notice"
      class="text-center text-sm font-semibold text-primary"
    >
      Overruled jointly — recorded in the Chronicle as precedent.
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
      <span class="font-semibold">{Enum.join(@room.next_bookends, " and ")}</span>
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
  """
  attr :seat, :map, default: nil
  attr :mode, :atom, default: :stage

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
          <span>{Enum.join(attempt.bookends, " + ")}</span>
          <span aria-hidden="true">→</span>
          <span class="font-semibold">
            {attempt.bridges |> Enum.map(& &1.bridge) |> Enum.join(" · ")}
          </span>
          <span>{attempt.closeness || "no verdict"}</span>
        </li>
      </ol>

      <div
        :if={@mode == :phone && @seat}
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

  # The rules name a rung; nobody says "deep_meld" out loud.
  defp band(nil), do: ""
  defp band(name), do: name |> to_string() |> String.replace("_", " ")

  defp waiting_line(nil), do: "Every bridge is in. The Assayer is looking at them."
  defp waiting_line(:grading), do: waiting_line(nil)
  defp waiting_line(:slow), do: "The Assayer is still reading. It does this sometimes."
  defp waiting_line(_), do: waiting_line(nil)

  defp waiting(%{open_seats: 0, seat_limit: seat_limit}),
    do: "All #{seat_limit} seats taken"

  defp waiting(%{open_seats: 1}), do: "Waiting for 1 more"
  defp waiting(%{open_seats: open}), do: "Waiting for #{open} more"

  defp reveal_arrival(%{melded?: true}), do: "meld"
  defp reveal_arrival(%{band: band}) when not is_nil(band), do: to_string(band)
  defp reveal_arrival(_), do: "no_verdict"

  defp closeness_presentation(%{band: :deep_meld}) do
    %{
      container_class: "border-2 border-primary/50 bg-primary/15 shadow-xl shadow-primary/20",
      number_class: "text-primary",
      badge_class: "bg-primary text-primary-content font-bold"
    }
  end

  defp closeness_presentation(%{melded?: true}) do
    %{
      container_class: "border-2 border-primary/40 bg-primary/10 shadow-lg shadow-primary/10",
      number_class: "text-primary",
      badge_class: "bg-primary text-primary-content font-bold"
    }
  end

  defp closeness_presentation(%{band: :almost}) do
    %{
      container_class: "border border-secondary/40 bg-base-200/40",
      number_class: "text-base-content",
      badge_class: "bg-secondary/20 text-secondary font-bold"
    }
  end

  defp closeness_presentation(%{band: :close}) do
    %{
      container_class: "border border-info/30 bg-base-200/40",
      number_class: "text-base-content",
      badge_class: "bg-info/20 text-info font-bold"
    }
  end

  defp closeness_presentation(%{band: :adjacent}) do
    %{
      container_class: "border border-base-300 bg-base-200/30",
      number_class: "text-base-content",
      badge_class: "bg-base-300 text-base-content/80 font-bold"
    }
  end

  defp closeness_presentation(%{band: :miss}) do
    %{
      container_class: "border border-base-300 bg-base-200/30",
      number_class: "text-base-content/85",
      badge_class: "bg-base-300 text-base-content/80 font-bold"
    }
  end

  defp closeness_presentation(_reveal) do
    %{
      container_class: "border border-base-300 bg-base-200/30",
      number_class: "text-base-content",
      badge_class: "bg-base-300 text-base-content/70 font-bold"
    }
  end

  defp your_fairness_tap(room, seat) do
    room[:your_tap] || (room[:fairness_taps] && seat && room.fairness_taps[seat.id])
  end

  defp your_bookends_tap(room, seat) do
    room[:your_bookends_tap] ||
      (room[:bookends_taps] && seat && room.bookends_taps[seat.id])
  end

  defp you?(seat, bridge), do: seat != nil and seat.id == bridge.seat_id

  defp find_own_couple(pairs, %{id: seat_id}) when is_list(pairs) do
    Enum.find(pairs, fn p -> p.couple? and seat_id in p.seat_ids end)
  end

  defp find_own_couple(_pairs, _seat), do: nil

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

  attr :room, :map, required: true

  def foley_switches(assigns) do
    ~H"""
    <div :if={@room[:speaker?]} class="flex items-center gap-3 text-xs opacity-80">
      <label class="flex items-center gap-1.5 cursor-pointer">
        <input
          type="checkbox"
          data-role="voice-switch"
          checked={@room[:voice] || false}
          phx-click="toggle_voice"
          class="checkbox checkbox-xs"
        />
        <span>Voice</span>
      </label>
      <label class="flex items-center gap-1.5 cursor-pointer">
        <input
          type="checkbox"
          data-role="house-loop-switch"
          checked={@room[:house_loop_only] || false}
          phx-click="toggle_house_loop_only"
          class="checkbox checkbox-xs"
        />
        <span>House loop only</span>
      </label>
    </div>
    """
  end

  attr :speaker, :boolean, default: false

  def foley_hook(assigns) do
    ~H"""
    <div id="foley-container" phx-hook=".Foley" data-speaker={to_string(@speaker)} class="hidden">
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Foley">
      export default {
        mounted() {
          this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches
          if (this.reducedMotion) return

          this.speaker = this.el.dataset.speaker === "true"
          this.ctx = null
          this.musicBus = null
          this.stingsBus = null
          this.voiceBus = null
          this.musicSource = null
          this.audioBuffers = new Map()

          this.initAudio = () => {
            if (this.ctx) return
            const AudioContext = window.AudioContext || window.webkitAudioContext
            if (!AudioContext) return
            this.ctx = new AudioContext()

            this.musicBus = this.ctx.createGain()
            this.stingsBus = this.ctx.createGain()
            this.voiceBus = this.ctx.createGain()

            this.musicBus.gain.setValueAtTime(0.7, this.ctx.currentTime)
            this.stingsBus.gain.setValueAtTime(1.0, this.ctx.currentTime)
            this.voiceBus.gain.setValueAtTime(1.0, this.ctx.currentTime)

            this.musicBus.connect(this.ctx.destination)
            this.stingsBus.connect(this.ctx.destination)
            this.voiceBus.connect(this.ctx.destination)

            this.updateTapForSound()
          }

          this.updateTapForSound = () => {
            const tapBtn = document.getElementById("tap-for-sound")
            if (tapBtn) {
              if (this.ctx && this.ctx.state === "running") {
                tapBtn.style.display = "none"
              } else {
                tapBtn.style.display = ""
              }
            }
          }

          this.resumeAudio = async () => {
            this.initAudio()
            if (this.ctx && this.ctx.state !== "running") {
              await this.ctx.resume()
            }
            this.updateTapForSound()
          }

          const tapBtn = document.getElementById("tap-for-sound")
          if (tapBtn) {
            tapBtn.addEventListener("click", () => this.resumeAudio())
          }

          const speakerToggle = document.querySelector("[data-role=speaker-toggle]")
          if (speakerToggle) {
            speakerToggle.addEventListener("click", () => this.resumeAudio())
          }

          this.fetchBuffer = async (url) => {
            if (this.audioBuffers.has(url)) return this.audioBuffers.get(url)
            try {
              const res = await fetch(url)
              const arrayBuf = await res.arrayBuffer()
              const audioBuf = await this.ctx.decodeAudioData(arrayBuf)
              this.audioBuffers.set(url, audioBuf)
              return audioBuf
            } catch (err) {
              return null
            }
          }

          this.duckMusic = (durationSeconds = 2.0) => {
            if (!this.ctx || !this.musicBus) return
            const now = this.ctx.currentTime
            this.musicBus.gain.cancelScheduledValues(now)
            this.musicBus.gain.setTargetAtTime(0.15, now, 0.05)
            this.musicBus.gain.setTargetAtTime(0.7, now + durationSeconds, 0.2)
          }

          this.playEffect = async (url, bus, duckDuration = 2.0) => {
            if (this.reducedMotion) return
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

          this.handleEvent("foley:page", async ({path}) => {
            if (this.reducedMotion) return
            await this.resumeAudio()
            if (!this.ctx) return
            const trackUrl = path || "/audio/house-loop.mp3"
            const buf = await this.fetchBuffer(trackUrl)
            if (!buf) return

            if (this.musicSource) {
              try { this.musicSource.stop() } catch (_) {}
            }
            this.musicSource = this.ctx.createBufferSource()
            this.musicSource.buffer = buf
            this.musicSource.loop = true
            this.musicSource.connect(this.musicBus)
            this.musicSource.start(0)
          })

          this.handleEvent("foley:beat", async () => {
            this.playEffect("/audio/beat.mp3", this.stingsBus, 2.5)
          })

          this.handleEvent("foley:sting", async ({band}) => {
            const bandName = (band || "miss").toString().replace("_", "-")
            this.playEffect(`/audio/sting-${bandName}.mp3`, this.stingsBus, 2.0)
          })

          this.handleEvent("foley:ending", async ({kind}) => {
            const endingKind = (kind === "meld") ? "meld" : "unmelded"
            const delayMs = (kind === "meld") ? 1800 : 0
            setTimeout(() => {
              this.playEffect(`/audio/ending-${endingKind}.mp3`, this.stingsBus, 0)
              if (this.musicSource) {
                try { this.musicSource.stop() } catch (_) {}
                this.musicSource = null
              }
            }, delayMs)
          })

          this.handleEvent("foley:stop", () => {
            if (this.musicSource) {
              try { this.musicSource.stop() } catch (_) {}
              this.musicSource = null
            }
          })

          this.updateTapForSound()
        },

        updated() {
          this.speaker = this.el.dataset.speaker === "true"
          this.updateTapForSound()
          if (!this.speaker && this.musicSource) {
            try { this.musicSource.stop() } catch (_) {}
            this.musicSource = null
          }
        },

        destroyed() {
          if (this.musicSource) {
            try { this.musicSource.stop() } catch (_) {}
            this.musicSource = null
          }
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
