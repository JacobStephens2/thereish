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

  @doc "Announcements about Gives: when new Pages have arrived, or when an Author run failed."
  def give_announcement(assigns) do
    ~H"""
    <div
      :if={@room[:give_announcement]}
      data-role="give-announcement"
      class="rounded-xl border border-primary/40 bg-primary/10 p-5 text-center transition-all"
    >
      <p class="text-xs uppercase tracking-widest font-semibold text-primary">New Setting Arrived</p>
      <p class="mt-1 text-2xl font-bold">
        The Author heard you: "{@room.give_announcement.give}"
      </p>
      <p class="mt-1 text-sm opacity-75">
        {@room.give_announcement.count} new Page{if @room.give_announcement.count == 1,
          do: "",
          else: "s"} added to tonight's pool.
      </p>
    </div>

    <div
      :if={@room[:give_failure]}
      data-role="give-failure"
      class="rounded-xl border border-warning/40 bg-warning/10 p-5 text-center transition-all"
    >
      <p class="text-xs uppercase tracking-widest font-semibold text-warning">Setting Notice</p>
      <p class="mt-1 text-lg font-medium text-warning-content">
        The Author couldn't write for "{@room.give_failure.give}": {@room.give_failure.reason}.
      </p>
      <p class="mt-1 text-sm opacity-70">
        Playing on from the existing pool.
      </p>
    </div>
    """
  end

  attr :room, :map, required: true

  @doc "The two words the Page hangs between, shown to everyone at once."
  def anchors(assigns) do
    ~H"""
    <div :if={@room.anchors} class="flex flex-col items-center gap-3">
      <p
        :if={@room[:page_give]}
        data-role="page-give"
        class="text-xs uppercase tracking-widest font-semibold text-primary"
      >
        Setting: {@room.page_give}
      </p>
      <div
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
    <div
      :if={@room.phase == :assaying}
      data-role="phase"
      data-step={@room.assayer_step || :grading}
      data-provisional-band={@room[:provisional_band]}
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
        {waiting_line(@room.assayer_step, @room[:provisional_band])}
      </p>
    </div>
    """
  end

  attr :room, :map, required: true
  attr :seat, :map, default: nil
  attr :mode, :atom, default: :phone

  @doc """
  The reveal: the Bridges side by side, then the number climbing into its band,
  then the punchline quip, then the Assayer's reasoning.

  In that order deliberately — the comparison lands first before the number does.
  The number arrives with weight, the band name arrives with it, and a Meld lands
  as a triumphant arrival distinct from a near miss or a deadpan miss.
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

      <div
        :if={@room.reveal.closeness}
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

          <span
            :if={@presentation.flavour}
            class={[
              "text-sm sm:text-base font-medium",
              if(@room.reveal.melded?, do: "font-semibold text-primary", else: "opacity-70")
            ]}
          >
            {@presentation.flavour}
          </span>
        </div>
      </div>

      <div
        :if={@room.reveal.closeness == nil}
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

      <ul class="flex w-full max-w-lg flex-col gap-6 text-center">
        <li
          :for={pair <- @room.reveal.pairs}
          data-role="pair"
          data-melded={to_string(pair.melded?)}
          class="flex flex-col items-center gap-3"
        >
          <p :if={length(@room.reveal.pairs) > 1} class="font-semibold text-sm opacity-80">
            {Enum.join(pair.names, " + ")} — {pair.closeness || "no verdict"} {band(pair.band)}
            <span :if={pair.melded?} data-role="pair-meld">· melded</span>
            <span :if={pair.overruled?} data-role="pair-overruled">· overruled</span>
          </p>

          <p
            :if={pair.quip}
            data-role="quip"
            class={[
              "font-serif italic font-medium leading-snug max-w-prose text-center",
              if(@mode == :stage,
                do: "text-3xl sm:text-4xl text-base-content",
                else: "text-xl sm:text-2xl text-base-content/90"
              )
            ]}
          >
            {pair.quip}
          </p>

          <div
            :if={pair.reasoning}
            class="flex flex-col items-center gap-1 rounded-xl bg-base-200/40 px-5 py-3 w-full border border-base-300/60"
          >
            <span class="text-xs font-semibold uppercase tracking-wider opacity-60">
              The Assayer's reasoning
            </span>
            <p
              data-role="reasoning"
              class={[
                "leading-relaxed",
                if(@mode == :stage,
                  do: "text-xl sm:text-2xl opacity-90",
                  else: "text-sm sm:text-base opacity-85"
                )
              ]}
            >
              {pair.reasoning}
            </p>
          </div>
        </li>
      </ul>

      <div
        :if={@mode == :phone && @seat && @room.reveal.closeness}
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
  defp waiting_line(step, provisional_band \\ nil)
  defp waiting_line(nil, _band), do: "Every bridge is in. The Assayer is looking at them."
  defp waiting_line(:grading, _band), do: waiting_line(nil)
  defp waiting_line(:slow, _band), do: "The Assayer is still reading. It does this sometimes."

  # The Author's pre-graded table puts a provisional band at eight seconds.
  defp waiting_line(:provisional, nil), do: "Still nothing. Hold on."

  defp waiting_line(:provisional, band) do
    "Provisional reading: #{band(band)} (from likely bridges). Still waiting on the Assayer."
  end

  defp waiting(%{open_seats: 0, seat_limit: seat_limit}),
    do: "All #{seat_limit} seats taken"

  defp waiting(%{open_seats: 1}), do: "Waiting for 1 more"
  defp waiting(%{open_seats: open}), do: "Waiting for #{open} more"

  defp reveal_arrival(%{melded?: true}), do: "meld"
  defp reveal_arrival(%{band: band}) when not is_nil(band), do: to_string(band)
  defp reveal_arrival(_), do: "no_verdict"

  defp closeness_presentation(%{melded?: true}) do
    %{
      container_class: "border-2 border-primary/40 bg-primary/10 shadow-lg shadow-primary/10",
      number_class: "text-primary",
      badge_class: "bg-primary text-primary-content font-bold",
      flavour: "One mind, two heads."
    }
  end

  defp closeness_presentation(%{band: :deep_meld}) do
    %{
      container_class: "border-2 border-primary/50 bg-primary/15 shadow-xl shadow-primary/20",
      number_class: "text-primary",
      badge_class: "bg-primary text-primary-content font-bold",
      flavour: "Two minds, one thought."
    }
  end

  defp closeness_presentation(%{band: :close}) do
    %{
      container_class: "border border-info/30 bg-base-200/40",
      number_class: "text-base-content",
      badge_class: "bg-info/20 text-info font-bold",
      flavour: "Passable."
    }
  end

  defp closeness_presentation(%{band: :adjacent}) do
    %{
      container_class: "border border-base-300 bg-base-200/30",
      number_class: "text-base-content",
      badge_class: "bg-base-300 text-base-content/80 font-bold",
      flavour: "Neighbouring ideas, distinct paths."
    }
  end

  defp closeness_presentation(%{band: :miss}) do
    %{
      container_class: "border border-base-300 bg-base-200/30",
      number_class: "text-base-content/85",
      badge_class: "bg-base-300 text-base-content/80 font-bold",
      flavour: "Different roads entirely."
    }
  end

  defp closeness_presentation(_) do
    %{
      container_class: "border border-base-300 bg-base-200/30",
      number_class: "text-base-content",
      badge_class: "bg-base-300 text-base-content/70 font-bold",
      flavour: nil
    }
  end

  defp your_fairness_tap(room, seat) do
    room[:your_tap] || (room[:fairness_taps] && seat && room.fairness_taps[seat.id])
  end

  defp you?(seat, bridge), do: seat != nil and seat.id == bridge.seat_id
end
