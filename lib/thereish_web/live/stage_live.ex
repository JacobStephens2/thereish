defmodule ThereishWeb.StageLive do
  @moduledoc """
  The laptop: the Room's public face, holding no Seat.

  It shows the same roster the phones show, the Room's Code — large while the
  Room is filling, small in the header for the rest of the night — and
  thereish.app, so the first thing a new player needs is already on the screen
  they are looking at.

  Sound starts on one deliberate tap. Opening the Stage claims nothing and
  plays nothing; the tap claims the Speaker and the Repertoire starts. That is
  the browser's autoplay rule met on purpose rather than discovered halfway
  through a Page, and it is the one gesture the Prologue can hang off.

  It also holds a Screen Wake Lock for as long as it is open. A reveal performed
  to a screen that went dark thirty seconds ago is not a reveal, and macOS will
  do exactly that during a quiet stretch while both players are typing on their
  phones.
  """
  use ThereishWeb, :live_view

  import ThereishWeb.RoomComponents

  alias Thereish.Rooms
  alias Thereish.Rooms.Code

  @impl true
  def mount(params, session, socket) do
    slug = Rooms.open!(params["slug"])
    device_token = ThereishWeb.DeviceToken.from_session(session)

    if connected?(socket) do
      Rooms.subscribe(slug)
      ThereishWeb.Presence.track_stage(socket, slug)
    end

    {:ok,
     socket
     |> assign(:slug, slug)
     |> assign(:join_url, join_url(slug))
     |> assign(:device_token, device_token)
     |> assign(:room, nil)
     |> resync()}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:device_token] do
      Rooms.release_speaker(socket.assigns.slug, socket.assigns.device_token)
    end

    :ok
  end

  # The one tap that opens the night's sound. Claiming the Speaker is what makes
  # the Repertoire arrive: the resync that follows sees a view that has just
  # claimed and pushes it the music to play.
  @impl true
  def handle_event("start_sound", _params, socket) do
    Rooms.start_sound(socket.assigns.slug, socket.assigns.device_token)
    {:noreply, resync(socket)}
  end

  def handle_event("play_prologue", _params, socket) do
    Rooms.play_prologue(socket.assigns.slug)
    {:noreply, resync(socket)}
  end

  def handle_event("skip_prologue", _params, socket) do
    Rooms.skip_prologue(socket.assigns.slug)
    {:noreply, resync(socket)}
  end

  def handle_event("toggle_quips", _params, socket) do
    Rooms.toggle(socket.assigns.slug, :quips)
    {:noreply, resync(socket)}
  end

  def handle_event("toggle_full_table", _params, socket) do
    Rooms.toggle(socket.assigns.slug, :full_table)
    {:noreply, resync(socket)}
  end

  def handle_event("set_music", %{"music" => music}, socket) do
    Rooms.set_music(socket.assigns.slug, music)
    {:noreply, resync(socket)}
  end

  def handle_event("next_music", _params, socket) do
    Rooms.next(socket.assigns.slug, socket.assigns.device_token)
    {:noreply, resync(socket)}
  end

  def handle_event("never_music", _params, socket) do
    Rooms.never(socket.assigns.slug, socket.assigns.device_token)
    {:noreply, resync(socket)}
  end

  @impl true
  def handle_info(:room_changed, socket), do: {:noreply, resync(socket)}

  # A recap landing is news for the book and for nothing on this screen. It
  # arrives here because the Scribe broadcasts on the Room's topic, and it is
  # ignored here on purpose rather than by a catch-all: a message this screen
  # does not know about should still be a crash.
  def handle_info(:chronicle_changed, socket), do: {:noreply, socket}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, socket}

  def handle_info({:voice_ready, attempt}, socket) do
    {:noreply, ThereishWeb.Foley.push_voice(socket, attempt, :verdict)}
  end

  def handle_info({:bookends_ready, attempt}, socket) do
    {:noreply, ThereishWeb.Foley.push_voice(socket, attempt, :bookends)}
  end

  # The stage holds no Seat, so it sees the Room the way anyone standing behind
  # the couch sees it.
  defp resync(socket) do
    old_room = socket.assigns[:room]
    new_room = Rooms.snapshot(socket.assigns.slug, nil, socket.assigns[:device_token])

    socket
    |> assign(:room, new_room)
    |> ThereishWeb.Foley.push_foley_events(old_room, new_room, stage?: true)
  end

  defp join_url(slug), do: url(~p"/r/#{slug}")

  defp chronicle_path(slug), do: ~p"/r/#{slug}/chronicle"

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="stage"
      phx-hook=".WakeLock"
      class="mx-auto flex h-screen max-h-screen w-full max-w-5xl flex-col overflow-hidden p-4 sm:p-6 md:px-8 md:py-5 select-none box-border"
    >
      <header class="flex items-center justify-between w-full shrink-0 gap-4">
        <div class="flex items-baseline gap-3 sm:gap-4">
          <h1 class="text-3xl sm:text-4xl font-semibold tracking-tight">
            <.link navigate={~p"/"} class="hover:opacity-80">Thereish</.link>
          </h1>
          <p
            :if={@room && not filling?(@room)}
            data-role="stage-code"
            data-size="small"
            class="font-mono text-lg sm:text-xl font-bold tracking-[0.25em] opacity-80"
          >
            {Code.shout(@slug)}
          </p>
        </div>
        <div class="flex items-center gap-3 sm:gap-4">
          <.tap_for_sound
            :if={offer_tap?(@room) and not filling?(@room)}
            size={:small}
            pulse={not @room.speaker_claimed?}
          />
          <.foley_switches :if={@room} room={@room} />
          <.link
            navigate={chronicle_path(@slug)}
            class="text-sm sm:text-base font-medium underline opacity-70 hover:opacity-100"
          >
            The Chronicle
          </.link>
        </div>
      </header>

      <div
        data-role="stage-body"
        class="flex-1 min-h-0 overflow-y-auto w-full"
      >
        <div class="flex min-h-full flex-col items-center justify-center gap-[clamp(0.5rem,1.8vh,1.5rem)] py-2">
          <section
            :if={@room && filling?(@room)}
            data-role="waiting-stage"
            class="flex flex-col items-center justify-center gap-[clamp(0.4rem,1.6vh,1.25rem)] text-center"
          >
            <p class="text-xs uppercase tracking-widest font-semibold text-primary">Code</p>
            <p
              data-role="stage-code"
              data-size="large"
              class="font-mono font-bold leading-none tracking-[0.15em] text-[clamp(4rem,18vw,10rem)]"
            >
              {Code.shout(@slug)}
            </p>
            <.tap_for_sound :if={offer_tap?(@room)} size={:large} pulse={not @room.speaker_claimed?} />

            <div
              :if={@room[:prologue]}
              data-role="prologue-stage"
              class="flex flex-col items-center gap-3 max-w-lg mx-auto"
            >
              <p data-role="prologue-words" class="text-base sm:text-lg leading-relaxed opacity-90">
                {@room.prologue.text}
              </p>
              <button
                type="button"
                phx-click="skip_prologue"
                data-role="prologue-skip"
                class="btn btn-ghost btn-xs text-xs opacity-70 hover:opacity-100"
              >
                Skip
              </button>
            </div>

            <button
              :if={is_nil(@room[:prologue]) and not offer_tap?(@room)}
              type="button"
              phx-click="play_prologue"
              data-role="play-prologue"
              class="btn btn-outline btn-xs sm:btn-sm opacity-70 hover:opacity-100"
            >
              Play the Prologue
            </button>
          </section>

          <section
            :if={@room.phase == :giving}
            data-role="giving-stage"
            class="flex flex-col items-center justify-center gap-3 text-center"
          >
            <p class="text-xs uppercase tracking-widest font-semibold text-primary">Gives</p>
            <p class="text-2xl font-semibold">
              Waiting for Gives: {@room.gives_in} of {length(@room.seats)}
            </p>
            <div data-role="stage-cards" class="flex items-center justify-center gap-4 mt-2">
              <div
                :for={seat <- @room[:seats] || []}
                :if={seat[:mask] == :face_down}
                title={"#{seat.name}'s Give landed"}
              >
                <span class="sr-only">{seat.name}</span>
                <.seat_mask seat={seat} size={:md} />
              </div>
            </div>
          </section>

          <section
            :if={@room.phase == :writing && is_nil(@room[:author_failure])}
            data-role="writing-stage"
            class="flex flex-col items-center justify-center gap-3 text-center"
          >
            <.author_writing room={@room} mode={:stage} />
          </section>

          <section
            :if={@room.phase == :writing && @room[:author_failure]}
            data-role="author-failure"
            class="flex flex-col items-center gap-3 rounded-xl border border-warning/40 bg-warning/10 p-5 text-center"
          >
            <p class="text-xs uppercase tracking-widest font-semibold text-warning">Give Notice</p>
            <p class="text-2xl font-semibold">
              The Author couldn't write from these Gives: {@room.author_failure}
            </p>
          </section>

          <.attempt room={@room} />

          <.bookends room={@room} mode={:stage} />

          <.bridge_markers room={@room} />

          <.assaying room={@room} />

          <.reveal room={@room} mode={:stage} />

          <.overrule_banner room={@room} />

          <.carry_forward room={@room} />

          <.reveal_hold room={@room} />

          <.ending room={@room} mode={:stage} />
        </div>
      </div>

      <footer
        data-role="stage-foot"
        class="flex flex-col items-stretch gap-1 border-t border-base-content/10 pt-2 shrink-0 text-xs sm:text-sm opacity-80"
      >
        <div class="flex flex-wrap items-center justify-between gap-x-6 gap-y-1">
          <p class={["opacity-70", filling?(@room) && "text-base sm:text-2xl"]}>
            Join at <.join_at url={@join_url} class="font-semibold" />
            <span :if={@room && @room[:quip]} data-role="stage-quip"> — {@room.quip}</span>
          </p>
          <.roster room={@room} mode={:stage} />
        </div>
        <.now_playing :if={@room} room={@room} />
        <Layouts.made_by :if={filling?(@room)} size={:stage} />
      </footer>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".WakeLock">
        export default {
          async mounted() {
            this.lock = null
            this.acquire = async () => {
              if (document.visibilityState !== "visible" || this.lock) return
              try {
                this.lock = await navigator.wakeLock.request("screen")
                this.lock.addEventListener("release", () => { this.lock = null })
              } catch (_error) {
                // No wake lock here — an insecure context, or a browser without
                // the API. The stage still works; the screen may sleep.
              }
            }
            if (!("wakeLock" in navigator)) return
            // The lock is dropped whenever the tab is hidden, so it has to be
            // taken again every time the laptop comes back.
            this.onVisible = () => this.acquire()
            document.addEventListener("visibilitychange", this.onVisible)
            await this.acquire()
          },
          destroyed() {
            document.removeEventListener("visibilitychange", this.onVisible)
            if (this.lock) this.lock.release()
          }
        }
      </script>

      <.foley_hook speaker={@room && @room.speaker?} />
    </main>
    """
  end

  attr :room, :map, required: true

  # Issue #82 established the Stage marker with a name chip. Issue #86 replaces
  # this chip with the Seat's Mask (or face-down card before the first reveal,
  # or colour dot if no Mask).
  defp bridge_markers(assigns) do
    ~H"""
    <section
      :if={@room.phase in [:bridging, :assaying]}
      data-role="bridge-markers"
      class="flex flex-wrap items-center justify-center gap-4"
      aria-label="Bridges landed"
    >
      <div
        :for={seat <- @room.seats}
        data-role="bridge-marker"
        data-seat={seat.id}
        data-color={seat[:colour]}
        data-state={if seat.committed?, do: "lit", else: "dim"}
        class="bridge-marker relative flex items-center justify-center rounded-xl border-2 p-1.5 transition-all"
        style={"--seat-color: #{seat_colour(seat)}"}
        title={seat.name}
      >
        <span class="sr-only">{seat.name}</span>
        <.seat_mask seat={seat} size={:md} />
      </div>
    </section>
    """
  end

  # The Room is still filling: nothing is in play yet, so the Code is the
  # biggest thing on the screen. From the first Give on it moves to the header
  # and the Page takes the middle.
  defp filling?(nil), do: false
  defp filling?(room), do: room.phase == :waiting

  # The tap is offered until this Stage holds the Speaker — including to a Stage
  # opened halfway through the night, which is how it joins the music.
  defp offer_tap?(nil), do: false
  defp offer_tap?(room), do: not room.speaker?

  attr :size, :atom, default: :small

  # It pulses while nobody is speaking, because then it is the thing to do
  # next. Once a phone holds the Speaker the Stage is quiet on purpose, so the
  # tap waits there without asking for attention.
  attr :pulse, :boolean, default: true

  defp tap_for_sound(assigns) do
    ~H"""
    <button
      type="button"
      id="tap-for-sound"
      data-role="tap-for-sound"
      phx-click="start_sound"
      class={[
        "btn",
        @pulse && "animate-pulse",
        if(@size == :large,
          do: "btn-primary btn-lg text-lg",
          else: "btn-outline btn-xs sm:btn-sm"
        )
      ]}
    >
      Tap for sound
    </button>
    """
  end
end
