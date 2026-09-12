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
      <%= if @seat[:mask] && @seat.mask not in [nil, :dot, :face_down] do %>
        <img
          src={@seat.mask[:url] || @seat.mask["url"] || @seat.mask}
          alt={@seat.name}
          data-role="seat-mask"
          class={[
            "rounded object-cover border border-base-300",
            if(@mode == :stage, do: "size-3.5", else: "size-5")
          ]}
        />
      <% else %>
        <%= if @seat[:mask] == :face_down do %>
          <span
            data-role="mask-face-down"
            data-seat={@seat.id}
            class={[
              "rounded border flex items-center justify-center text-[10px] opacity-80",
              if(@mode == :stage, do: "size-3", else: "size-4")
            ]}
            style={"border-color: #{@seat[:colour] || "var(--color-primary, currentColor)"}; color: #{@seat[:colour] || "var(--color-primary, currentColor)"}; background-color: color-mix(in oklab, #{@seat[:colour] || "var(--color-primary, currentColor)"} 15%, transparent);"}
            title="Mask face down"
          >
            🂠
          </span>
        <% else %>
          <span
            data-role="seat-colour-dot"
            class={[
              "rounded-full",
              if(@mode == :stage, do: "size-1.5", else: "size-2")
            ]}
            style={"background-color: #{@seat[:colour] || "var(--color-primary, currentColor)"}"}
            aria-hidden="true"
          ></span>
        <% end %>
      <% end %>
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

  defp mask_url(%{mask: url}) when is_binary(url) and url != "", do: url
  defp mask_url(%{mask: mask}) when is_map(mask), do: mask[:url] || mask["url"]
  defp mask_url(%{"mask" => mask}) when is_map(mask), do: mask[:url] || mask["url"]
  defp mask_url(_), do: nil

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
    standard_reveal(assigns)
  end

  defp standard_reveal(assigns) do
    presentation = assigns.room.reveal && closeness_presentation(assigns.room.reveal)
    assigns = assign(assigns, :presentation, presentation)

    ~H"""
    <section
      :if={@room.reveal}
      id="reveal-performance"
      data-role="reveal"
      data-arrival={reveal_arrival(@room.reveal)}
      data-mode={@mode}
      class={[
        "flex flex-col items-center w-full mx-auto",
        if(@mode == :stage, do: "gap-[clamp(0.5rem,1.8vh,1.5rem)] max-w-4xl", else: "gap-8 max-w-xl")
      ]}
    >
      <div
        data-role="comparison"
        style="animation: reveal-comparison 0.35s ease-out both;"
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
          <div class="flex items-center gap-1.5 text-xs uppercase tracking-wider opacity-60">
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
        style="animation: reveal-closeness 0.5s cubic-bezier(0.16, 1, 0.3, 1) 0.35s both;"
        class={[
          "flex flex-col items-center justify-center rounded-2xl transition-all duration-500 w-full max-w-sm text-center",
          if(@mode == :stage, do: "px-6 py-2 sm:py-3", else: "px-8 py-6"),
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
            style="animation: band-arrive 0.4s ease-out 0.8s both;"
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
          @mode == :stage and first_reveal_happened?(@room) and @room.phase != :closed and
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
          <%= if is_map(seat[:mask]) and (seat.mask[:url] || seat.mask["url"]) do %>
            <img
              src={seat.mask[:url] || seat.mask["url"]}
              alt={seat.name}
              data-role="seat-mask"
              class="size-16 rounded-xl object-cover border-2 shadow-md"
              style={"border-color: #{seat[:colour] || "var(--color-primary, currentColor)"};"}
            />
          <% else %>
            <div
              class="size-16 rounded-xl border-2 flex items-center justify-center shadow-md bg-base-200"
              style={"border-color: #{seat[:colour] || "var(--color-primary, currentColor)"};"}
            >
              <span
                data-role="seat-colour-dot"
                class="size-6 rounded-full"
                style={"background-color: #{seat[:colour] || "var(--color-primary, currentColor)"}"}
                aria-hidden="true"
              ></span>
            </div>
          <% end %>
          <span class="text-xs font-semibold opacity-75">{seat.name}</span>
        </div>
      </div>

      <.fairness_controls
        :if={@mode in [:phone, :quiet] && @seat && !@room[:late?] && @room.reveal.closeness}
        room={@room}
        seat={@seat}
      />

      <div
        :if={(@room[:closed] || @room.phase == :closed) && gives_list(@room) != []}
        data-role="gives"
        class={[
          "flex flex-col items-center w-full",
          if(@mode == :stage, do: "gap-2", else: "gap-3")
        ]}
      >
        <.caption>Gives</.caption>
        <div class="flex flex-wrap items-stretch justify-center gap-3 sm:gap-4 w-full">
          <div
            :for={give <- gives_list(@room)}
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
            {Thereish.Chronicle.FairnessTap.label_human(tap)}
          </span>
          recorded
        </div>
      <% end %>
    </div>
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
      <p :if={@seat && !@room[:late?] && @room.overrule.you_proposed?} data-role="overrule-pending">
        You proposed an overrule. Waiting for everyone to agree.
      </p>

      <div
        :if={@seat && !@room[:late?] && !@room.overrule.you_agreed?}
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
        :if={
          @seat && !@room[:late?] && @room.overrule.you_agreed? &&
            !@room.overrule.you_proposed?
        }
        data-role="overrule-pending"
      >
        You agreed. Waiting for everyone to agree.
      </p>

      <p :if={is_nil(@seat) or @room[:late?]} data-role="overrule-pending" class="opacity-80">
        <span class="font-semibold">{@room.overrule.proposer_name}</span>
        proposed an overrule. Waiting for the Room to agree.
      </p>
    </div>

    <p
      :if={@room.reveal && @room.reveal[:overruled?]}
      data-role="overruled-notice"
      class="text-center text-sm font-semibold text-primary"
    >
      Overruled jointly - recorded in the Chronicle as precedent.
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

  defp waiting(%{seats: [_]}), do: "Waiting for 1 more"
  defp waiting(_), do: nil

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
      <label :if={@room[:speaker?]} class="flex items-center gap-1.5 cursor-pointer">
        <input
          id="voice-switch"
          phx-hook=".VoiceSwitch"
          type="checkbox"
          data-role="voice-switch"
          data-active="false"
          class="checkbox checkbox-xs"
        />
        <span>Voice</span>
      </label>
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
      <label class="flex items-center gap-1.5 cursor-pointer">
        <input
          type="checkbox"
          data-role="full-table-switch"
          data-active={to_string(Map.get(@room, :full_table, true))}
          checked={Map.get(@room, :full_table, true)}
          phx-click="toggle_full_table"
          class="checkbox checkbox-xs"
        />
        <span>Full table: one Bookend from every player's Give, and every bridge carries forward</span>
      </label>
      <p
        :if={length(Map.get(@room, :seats, []) || []) == 2}
        data-role="full-table-note"
        class="opacity-70"
      >
        Matters from three Seats
      </p>
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
    <script :type={Phoenix.LiveView.ColocatedHook} name=".VoiceSwitch">
      export default {
        mounted() {
          this.syncUI = () => {
            let enabled = false
            try {
              enabled = localStorage.getItem("foley:voice") === "on"
            } catch (_) {}
            this.el.checked = enabled
            this.el.dataset.active = enabled ? "true" : "false"
            this.el.setAttribute("aria-checked", enabled ? "true" : "false")
          }
          this.syncUI()

          this.handleChange = () => {
            const next = !!this.el.checked
            try {
              localStorage.setItem("foley:voice", next ? "on" : "off")
            } catch (_) {}
            this.syncUI()
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

  defp first_reveal_happened?(room) do
    room[:phase] in [:reveal, :closed, :revealed] or
      (is_list(room[:played]) and room.played != [])
  end

  defp gives_list(room) do
    cond do
      is_map(room[:reveal]) and is_list(room.reveal[:gives]) ->
        room.reveal.gives

      is_list(room[:gives]) ->
        room.gives

      true ->
        []
    end
  end

  def now_playing_text(nil), do: nil

  def now_playing_text(room) do
    cond do
      to_string(room[:music]) == "off" and
          (room[:loop] != nil or room[:playing] != nil or
             room[:phase] in [:bridging, :assaying, :revealed, :closed]) ->
        "Music is off"

      room[:playing] && room.playing[:kind] in ["track", "vamp"] ->
        if first_reveal_happened?(room) and room.playing[:title] do
          "Now playing: #{room.playing.title} (written for this Page)"
        else
          "Now playing: written for this Page"
        end

      room[:playing] && room.playing[:kind] == "holdover" && room.playing[:title] ->
        "Now playing: #{room.playing.title} (last Page's Track)"

      room[:playing] && room.playing[:kind] == "repertoire" && room.playing[:title] ->
        "Now playing: #{room.playing.title} (the Repertoire)"

      room[:track] && room.track[:path] && room.track[:title] ->
        if first_reveal_happened?(room) do
          "Now playing: #{room.track.title} (written for this Page)"
        else
          "Now playing: written for this Page"
        end

      room[:track] && room.track[:path] ->
        nil

      room[:loop] ->
        title = room.loop[:title] || room.loop[:name]
        "Now playing: #{title} (the Repertoire)"

      true ->
        nil
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
          this.isReducedMotion = () => window.matchMedia("(prefers-reduced-motion: reduce)").matches
          this.speaker = this.el.dataset.speaker === "true"
          this.mode = this.el.dataset.mode || (this.speaker ? "speaker" : "local")
          // Read the speaker off the DOM rather than off the last `updated()`:
          // the tap that claims the Speaker is answered with the patch and the
          // first `foley:page` together, and a stale flag would swallow it.
          this.canPlay = () => !this.isReducedMotion() && this.el.dataset.speaker === "true"
          this.ctx = null
          this.musicBus = null
          this.stingsBus = null
          this.voiceBus = null
          this.musicSource = null
          this.voiceSource = null
          this.voiceObserver = null
          this.currentVoiceAttempt = null
          this.musicOff = false
          this.audioBuffers = new Map()

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
            this.stopVoice()
            this.currentVoiceAttempt = null
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

          this.handleEvent("foley:voice", async ({url, attempt}) => {
            if (!this.canPlay()) return
            let voiceEnabled = false
            try {
              voiceEnabled = localStorage.getItem("foley:voice") === "on"
            } catch (_) {}
            if (!voiceEnabled) return

            await this.resumeAudio()
            if (!this.ctx) return

            this.stopVoice()
            this.currentVoiceAttempt = attempt

            const isRevealReady = () =>
              document.querySelector("[data-role=quip]") ||
              document.querySelector("[data-role=fairness-controls]") ||
              document.querySelector("[data-role=closeness-display]") ||
              document.querySelector("[data-role=no-verdict]")

            const playWhenReady = (buf) => {
              if (!buf || !this.ctx || this.currentVoiceAttempt !== attempt) return
              if (!isRevealReady()) return

              this.currentVoiceAttempt = attempt
              this.playVoiceBuffer(buf, true)
            }

            const voiceUrl = url
            const bufPromise = this.fetchBuffer(voiceUrl)

            if (isRevealReady()) {
              const buf = await bufPromise
              playWhenReady(buf)
            } else {
              const observer = new MutationObserver(async (_mutations, obs) => {
                if (this.currentVoiceAttempt !== attempt) {
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
            if (this.isReducedMotion()) return
            await this.playCommitTick()
          })

          this.handleEvent("foley:own-commit", async () => {
            let enabled = true
            try {
              enabled = localStorage.getItem("foley:local-sounds") !== "off"
            } catch (_) {}
            if (!enabled || this.isReducedMotion()) return
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
            this.stopVoice()
            this.currentVoiceAttempt = null
            this.stopMusic()
          })
        },

        updated() {
          this.speaker = this.el.dataset.speaker === "true"
          this.meldCueDelayMs = (this.parseDelay || parseInt)(this.el.dataset.meldCueDelayMs, 1800)
          this.mode = this.el.dataset.mode || (this.speaker ? "speaker" : "local")
          if (!this.speaker) {
            if (this.clearEndingTimeout) this.clearEndingTimeout()
            this.stopVoice()
            this.currentVoiceAttempt = null
            this.stopMusic()
          }
        },

        destroyed() {
          if (this.clearEndingTimeout) this.clearEndingTimeout()
          if (this.onFormSubmit) document.removeEventListener("submit", this.onFormSubmit)
          if (this.onCommitClick) document.removeEventListener("click", this.onCommitClick)
          if (this.onTapClick) document.removeEventListener("click", this.onTapClick)
          this.stopVoice()
          this.currentVoiceAttempt = null
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
