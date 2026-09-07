defmodule MeaningGameWeb.StageLive do
  @moduledoc """
  The laptop: the Room's public face, holding no Seat.

  It shows the same roster the phones show, and the URL to type to get into it,
  so the first thing a new player needs is already on the screen they are
  looking at.

  It also holds a Screen Wake Lock for as long as it is open. A reveal performed
  to a screen that went dark thirty seconds ago is not a reveal, and macOS will
  do exactly that during a quiet stretch while both players are typing on their
  phones.
  """
  use MeaningGameWeb, :live_view

  import MeaningGameWeb.RoomComponents

  alias MeaningGame.Rooms

  @impl true
  def mount(params, session, socket) do
    slug = Rooms.open!(params["slug"])
    device_token = MeaningGameWeb.DeviceToken.from_session(session)

    if connected?(socket) do
      Rooms.subscribe(slug)
      Rooms.claim_speaker(slug, device_token)
      MeaningGameWeb.Presence.track_stage(socket, slug)
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

  @impl true
  def handle_event("toggle_voice", _params, socket) do
    Rooms.set_voice(socket.assigns.slug, !socket.assigns.room.voice)
    {:noreply, resync(socket)}
  end

  def handle_event("set_music", %{"music" => music}, socket) do
    Rooms.set_music(socket.assigns.slug, music)
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
    {:noreply, MeaningGameWeb.Foley.push_voice(socket, attempt)}
  end

  # The stage holds no Seat, so it sees the Room the way anyone standing behind
  # the couch sees it.
  defp resync(socket) do
    old_room = socket.assigns[:room]
    new_room = Rooms.snapshot(socket.assigns.slug, nil, socket.assigns[:device_token])

    socket
    |> assign(:room, new_room)
    |> MeaningGameWeb.Foley.push_foley_events(old_room, new_room)
  end

  defp join_url(slug), do: url(~p"/r/#{slug}")

  defp chronicle_path(slug), do: ~p"/r/#{slug}/chronicle"

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="stage"
      phx-hook=".WakeLock"
      class="mx-auto flex h-screen max-h-screen w-full max-w-5xl flex-col justify-between p-4 sm:p-6 md:px-8 md:py-5"
    >
      <header class="flex items-center justify-between shrink-0 gap-4">
        <h1 class="text-3xl sm:text-4xl font-semibold tracking-tight">Thereish</h1>
        <div class="flex items-center gap-3 sm:gap-4">
          <button
            :if={@room && @room.speaker?}
            type="button"
            id="tap-for-sound"
            data-role="tap-for-sound"
            class="btn btn-outline btn-xs sm:btn-sm animate-pulse"
          >
            Tap for sound
          </button>
          <.foley_switches :if={@room} room={@room} />
          <.link
            navigate={chronicle_path(@slug)}
            class="text-sm sm:text-base font-medium underline opacity-70 hover:opacity-100"
          >
            The Chronicle
          </.link>
        </div>
      </header>

      <div class="flex flex-1 flex-col items-center justify-center my-auto min-h-0 w-full gap-[clamp(0.5rem,1.8vh,1.5rem)]">
        <section
          :if={@room.phase == :giving}
          data-role="giving-stage"
          class="flex flex-col items-center justify-center gap-3 text-center"
        >
          <p class="text-xs uppercase tracking-widest font-semibold text-primary">Settings</p>
          <p class="text-2xl font-semibold">
            Waiting for settings: {@room.gives_in} of {length(@room.seats)}
          </p>
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
          <p class="text-xs uppercase tracking-widest font-semibold text-warning">Setting Notice</p>
          <p class="text-2xl font-semibold">
            The Author couldn't write from these settings: {@room.author_failure}
          </p>
        </section>

        <.attempt room={@room} />

        <.bookends room={@room} mode={:stage} />

        <.assaying room={@room} />

        <.reveal room={@room} mode={:stage} />

        <.overrule_banner room={@room} />

        <.carry_forward room={@room} />

        <.ending room={@room} mode={:stage} />
      </div>

      <footer class="flex flex-wrap items-center justify-between gap-x-6 gap-y-1 border-t border-base-content/10 pt-2 shrink-0 text-xs sm:text-sm opacity-80">
        <p class="opacity-70">
          Join at
          <span data-role="join-url" class="font-mono font-semibold">{display_url(@join_url)}</span>
          <span :if={@room && @room[:quip]} data-role="stage-quip"> — {@room.quip}</span>
        </p>
        <.roster room={@room} mode={:stage} />
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

  defp display_url(url), do: String.replace_prefix(url, "https://", "")
end
