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
  def mount(params, _session, socket) do
    slug = Rooms.open!(params["slug"] || Rooms.default_slug())

    if connected?(socket), do: Rooms.subscribe(slug)

    {:ok,
     socket
     |> assign(:slug, slug)
     |> assign(:join_url, join_url(params))
     |> resync()}
  end

  @impl true
  def handle_info(:room_changed, socket), do: {:noreply, resync(socket)}

  # The stage holds no Seat, so it sees the Room the way anyone standing behind
  # the couch sees it.
  defp resync(socket), do: assign(socket, :room, Rooms.snapshot(socket.assigns.slug, nil))

  defp join_url(%{"slug" => slug}), do: url(~p"/r/#{slug}")
  defp join_url(_params), do: url(~p"/")

  defp chronicle_path(slug) do
    if slug == Rooms.default_slug(), do: ~p"/chronicle", else: ~p"/r/#{slug}/chronicle"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="stage"
      phx-hook=".WakeLock"
      class="mx-auto flex min-h-screen max-w-3xl flex-col justify-center gap-12 px-8 py-16"
    >
      <header class="flex flex-col gap-2">
        <div class="flex items-center justify-between">
          <h1 class="text-4xl font-semibold">Meaning Game</h1>
          <.link
            navigate={chronicle_path(@slug)}
            class="text-base font-medium underline opacity-70 hover:opacity-100"
          >
            The Chronicle
          </.link>
        </div>
        <p class="text-xl opacity-70">
          Join at <span data-role="join-url" class="font-mono">{display_url(@join_url)}</span>
        </p>
      </header>

      <.attempt room={@room} />

      <.anchors room={@room} />

      <.assaying room={@room} />

      <.reveal room={@room} mode={:stage} />

      <.overrule_banner room={@room} />

      <.carry_forward room={@room} />

      <.ending room={@room} />

      <section class="flex flex-col gap-4">
        <h2 class="text-sm uppercase tracking-wide opacity-60">In the Room</h2>
        <.roster room={@room} />
      </section>

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
    </main>
    """
  end

  defp display_url(url), do: String.replace_prefix(url, "https://", "")
end
