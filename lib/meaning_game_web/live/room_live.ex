defmodule MeaningGameWeb.RoomLive do
  @moduledoc """
  A phone in the Room: type a name, or already be someone.

  Mount asks the Room whether this browser's device token already holds a Seat.
  If it does — a locked phone waking up, a tab reopened days later — there is no
  name form and no ceremony; the player is simply back where they were. That is
  the whole of the rejoin story, and it is the same code path as a first visit.

  Every refresh of this view is a full snapshot from the Room, never a patch
  applied to what the view happened to be holding, so a phone that missed
  messages while asleep cannot end up subtly out of date.

  The one thing this view holds that the Room does not is the Bridge being
  typed. An uncommitted Bridge is nobody's business, including the Room's, so it
  lives in the text field until the player commits it — which is also why the
  field carries no value the server sets: a re-render caused by the other phone
  must never rewrite what this one is in the middle of typing.
  """
  use MeaningGameWeb, :live_view

  import MeaningGameWeb.RoomComponents

  alias MeaningGame.Rooms
  alias MeaningGame.Rooms.Seat
  alias MeaningGameWeb.DeviceToken

  @impl true
  def mount(params, session, socket) do
    slug = Rooms.open!(params["slug"] || Rooms.default_slug())
    device_token = DeviceToken.from_session(session)

    if connected?(socket), do: Rooms.subscribe(slug)

    {:ok,
     socket
     |> assign(:slug, slug)
     |> assign(:device_token, device_token)
     |> assign(:name, "")
     |> assign(:error, nil)
     |> assign(:bridge_error, nil)
     |> assign(:seat, seat_for_device(slug, device_token))
     |> resync()}
  end

  @impl true
  def handle_event("join", %{"name" => name}, socket) do
    case Rooms.join(socket.assigns.slug, name, socket.assigns.device_token) do
      {:ok, seat} ->
        {:noreply, socket |> assign(seat: seat, error: nil) |> resync()}

      {:error, reason} ->
        {:noreply, assign(socket, name: name, error: message(reason))}
    end
  end

  def handle_event("commit_bridge", %{"bridge" => bridge}, socket) do
    case Rooms.commit_bridge(socket.assigns.slug, socket.assigns.seat.id, bridge) do
      :ok -> {:noreply, socket |> assign(:bridge_error, nil) |> resync()}
      {:error, reason} -> {:noreply, assign(socket, :bridge_error, message(reason))}
    end
  end

  # The phone woke up. Ask for the whole view rather than trusting what is on
  # screen, because whatever happened while the screen was off is unknowable
  # from here.
  def handle_event("resync", _params, socket), do: {:noreply, resync(socket)}

  @impl true
  def handle_info(:room_changed, socket), do: {:noreply, resync(socket)}

  defp seat_for_device(slug, device_token) do
    case Rooms.rejoin(slug, device_token) do
      {:ok, seat} -> seat
      :error -> nil
    end
  end

  defp resync(socket) do
    seat_id = socket.assigns.seat && socket.assigns.seat.id
    assign(socket, :room, Rooms.snapshot(socket.assigns.slug, seat_id))
  end

  defp message(:name_required), do: "Type a name first."
  defp message(:name_too_long), do: "That name is longer than #{Seat.name_max()} characters."
  defp message(:room_full), do: "Every seat is taken. Ask whoever is in there to make room."
  defp message(:could_not_join), do: "Something went wrong taking a seat. Try again."
  defp message(:bridge_required), do: "Write a word first."
  defp message(:already_committed), do: "That one is committed. No taking it back."
  defp message(:not_bridging), do: "Too late for this one."
  defp message(:no_such_seat), do: "You are not in this Room any more. Reload."

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="room"
      phx-hook=".ResyncOnWake"
      class="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-8 px-6 py-12"
    >
      <h1 class="text-2xl font-semibold">Meaning Game</h1>

      <form :if={@seat == nil} phx-submit="join" class="flex flex-col gap-2">
        <.input name="name" value={@name} label="Your name" autocomplete="off" autofocus />
        <p :if={@error} data-role="error" class="text-sm text-error">{@error}</p>
        <.button variant="primary">Join</.button>
      </form>

      <p :if={@seat} data-role="you" class="text-lg">
        You are <span class="font-semibold">{@seat.name}</span>.
      </p>

      <.anchors :if={@seat} room={@room} />

      <form
        :if={@seat && @room.phase == :bridging && @room.your_bridge == nil}
        id="bridge-form"
        data-role="bridge-form"
        phx-submit="commit_bridge"
        class="flex flex-col gap-2"
      >
        <.input
          name="bridge"
          value={nil}
          label="The word between them"
          autocomplete="off"
          autofocus
        />
        <p :if={@bridge_error} data-role="bridge-error" class="text-sm text-error">
          {@bridge_error}
        </p>
        <.button variant="primary">Commit</.button>
      </form>

      <div :if={@room.your_bridge && @room.phase != :reveal} class="flex flex-col gap-1">
        <p data-role="your-bridge" class="text-lg">
          You wrote <span class="font-semibold">{@room.your_bridge}</span>.
        </p>
        <p :if={@room.phase == :bridging} class="text-sm opacity-60">Waiting for the others.</p>
      </div>

      <.assaying room={@room} />

      <.reveal room={@room} />

      <section class="flex flex-col gap-2">
        <h2 class="text-sm uppercase tracking-wide opacity-60">In the Room</h2>
        <.roster room={@room} />
      </section>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ResyncOnWake">
        export default {
          mounted() {
            this.onVisible = () => {
              if (document.visibilityState === "visible") this.pushEvent("resync", {})
            }
            document.addEventListener("visibilitychange", this.onVisible)
          },
          destroyed() {
            document.removeEventListener("visibilitychange", this.onVisible)
          }
        }
      </script>
    </main>
    """
  end
end
