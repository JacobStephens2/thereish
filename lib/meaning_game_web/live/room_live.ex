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
