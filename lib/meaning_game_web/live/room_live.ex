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
  alias MeaningGame.Rooms.Code
  alias MeaningGame.Rooms.Seat
  alias MeaningGameWeb.DeviceToken

  @impl true
  def mount(params, session, socket) do
    slug = Rooms.open!(params["slug"])
    device_token = DeviceToken.from_session(session)

    if connected?(socket), do: Rooms.subscribe(slug)

    {:ok,
     socket
     |> assign(:slug, slug)
     |> assign(:join_url, url(~p"/r/#{slug}"))
     |> assign(:device_token, device_token)
     |> assign(:name, "")
     |> assign(:error, nil)
     |> assign(:bridge_error, nil)
     |> assign(:page_error, nil)
     |> assign(:give_input, "")
     |> assign(:give_error, nil)
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

  def handle_event("validate_bridge", %{"bridge" => bridge}, socket) do
    bookends = (socket.assigns.room && socket.assigns.room.bookends) || []
    trimmed = String.trim(bridge)

    error =
      if trimmed == "" do
        nil
      else
        case MeaningGame.Steward.Legality.check_bridge(trimmed, bookends) do
          :ok -> nil
          {:illegal, why} -> why
        end
      end

    {:noreply, assign(socket, :bridge_error, error)}
  end

  def handle_event("commit_bridge", %{"bridge" => bridge}, socket) do
    case Rooms.commit_bridge(socket.assigns.slug, socket.assigns.seat.id, bridge) do
      :ok -> {:noreply, socket |> assign(:bridge_error, nil) |> resync()}
      {:error, reason} -> {:noreply, assign(socket, :bridge_error, message(reason))}
    end
  end

  # Both phones can reach the same button, and on a couch both of them will.
  # Whichever tap lands second is answered by the Room with the state the first
  # one left, so there is nothing to say about it beyond showing what is there.
  def handle_event("next_attempt", _params, socket) do
    Rooms.next_attempt(socket.assigns.slug, socket.assigns.seat.id)

    {:noreply, resync(socket)}
  end

  def handle_event("next_page", _params, socket) do
    case Rooms.next_page(socket.assigns.slug, socket.assigns.seat.id) do
      :ok ->
        {:noreply, socket |> assign(:page_error, nil) |> resync()}

      {:error, reason} ->
        {:noreply, assign(socket, :page_error, message(reason))}
    end
  end

  def handle_event("propose_overrule", _params, socket) do
    Rooms.propose_overrule(socket.assigns.slug, socket.assigns.seat.id)

    {:noreply, resync(socket)}
  end

  def handle_event("agree_overrule", _params, socket) do
    Rooms.agree_overrule(socket.assigns.slug, socket.assigns.seat.id)

    {:noreply, resync(socket)}
  end

  def handle_event("decline_overrule", _params, socket) do
    Rooms.decline_overrule(socket.assigns.slug, socket.assigns.seat.id)

    {:noreply, resync(socket)}
  end

  def handle_event("fairness_tap", %{"label" => label}, socket) do
    if socket.assigns.seat do
      Rooms.record_fairness_tap(socket.assigns.slug, socket.assigns.seat.id, label)
    end

    {:noreply, resync(socket)}
  end

  def handle_event("submit_give", %{"give" => give}, socket) do
    trimmed = String.trim(give || "")

    if trimmed == "" do
      {:noreply, assign(socket, :give_error, "Type a setting first.")}
    else
      case Rooms.give(socket.assigns.slug, socket.assigns.seat.id, trimmed) do
        :ok ->
          {:noreply, socket |> assign(give_input: "", give_error: nil) |> resync()}

        {:error, reason} ->
          {:noreply, assign(socket, :give_error, message(reason))}
      end
    end
  end

  # The phone woke up. Ask for the whole view rather than trusting what is on
  # screen, because whatever happened while the screen was off is unknowable
  # from here.
  def handle_event("resync", _params, socket), do: {:noreply, resync(socket)}

  @impl true
  def handle_info(:room_changed, socket), do: {:noreply, resync(socket)}

  # A recap landing is news for the book and for nothing on this screen. It
  # arrives here because the Scribe broadcasts on the Room's topic, and it is
  # ignored here on purpose rather than by a catch-all: a message this screen
  # does not know about should still be a crash.
  def handle_info(:chronicle_changed, socket), do: {:noreply, socket}

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

  defp message(:give_required), do: "Type a setting first."
  defp message(:name_required), do: "Type a name first."
  defp message(:name_too_long), do: "That name is longer than #{Seat.name_max()} characters."
  defp message(:room_full), do: "Every seat is taken. Ask whoever is in there to make room."
  defp message(:could_not_join), do: "Something went wrong taking a seat. Try again."
  defp message(:bridge_required), do: "Write a word first."
  defp message(:already_committed), do: "That one is committed. No taking it back."
  defp message(:not_bridging), do: "Too late for this one."
  defp message(:no_such_seat), do: "You are not in this Room any more. Reload."
  defp message({:illegal_bridge, reason}), do: reason
  defp message(:pool_exhausted), do: "That's every Page for tonight."
  defp message(_), do: "Something went wrong. Try again."

  defp chronicle_path(slug), do: ~p"/r/#{slug}/chronicle"

  defp display_url(url), do: String.replace_prefix(url, "https://", "")

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="room"
      phx-hook=".ResyncOnWake"
      class="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-8 px-6 py-12"
    >
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-semibold">Meaning Game</h1>
        <.link
          navigate={chronicle_path(@slug)}
          class="text-sm font-medium underline opacity-70 hover:opacity-100"
        >
          The Chronicle
        </.link>
      </div>

      <section
        :if={@room.open_seats > 0}
        data-role="room-code"
        class="flex flex-col items-center gap-1 rounded-lg border border-base-300 px-4 py-6"
      >
        <p class="text-sm uppercase tracking-wide opacity-60">Code</p>
        <p data-role="code" class="font-mono text-5xl font-bold tracking-[0.3em]">
          {Code.shout(@slug)}
        </p>
        <p class="mt-2 text-center text-sm opacity-70">
          Read it aloud, or send <span data-role="join-url" class="font-mono">{display_url(@join_url)}</span>.
        </p>
      </section>

      <form :if={@seat == nil} phx-submit="join" class="flex flex-col gap-2">
        <.input name="name" value={@name} label="Your name" autocomplete="off" autofocus />
        <p :if={@error} data-role="error" class="text-sm text-error">{@error}</p>
        <.button variant="primary">Join</.button>
      </form>

      <p :if={@seat} data-role="you" class="text-lg">
        You are <span class="font-semibold">{@seat.name}</span>.
      </p>

      <.attempt :if={@seat} room={@room} />

      <.bookends :if={@seat} room={@room} />

      <form
        :if={@seat && @room.phase == :bridging && @room.your_bridge == nil}
        id="bridge-form"
        data-role="bridge-form"
        phx-change="validate_bridge"
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

      <div :if={@room.your_bridge && mid_page?(@room)} class="flex flex-col gap-1">
        <p data-role="your-bridge" class="text-lg">
          You wrote <span class="font-semibold">{@room.your_bridge}</span>.
        </p>
        <p :if={@room.phase == :bridging} class="text-sm opacity-60">Waiting for the others.</p>
      </div>

      <.assaying room={@room} />

      <.reveal room={@room} seat={@seat} mode={:phone} />

      <.overrule_banner room={@room} seat={@seat} />

      <div
        :if={@seat && @room.reveal && @room.overrule == nil && !@room.reveal.overruled?}
        class="flex justify-center"
      >
        <.button phx-click="propose_overrule" data-role="propose-overrule">
          Overrule the Assayer
        </.button>
      </div>

      <div
        :if={@seat && @room.phase == :reveal}
        class="flex flex-col items-center gap-2 border-t border-base-300 pt-6"
      >
        <.carry_forward room={@room} />
        <.button phx-click="next_attempt" data-role="again" variant="primary">
          Again — {Enum.join(@room.next_bookends, " and ")}
        </.button>
      </div>

      <.ending room={@room} />

      <div :if={@seat && @room.phase == :closed} class="flex flex-col items-center gap-2">
        <p :if={@page_error} data-role="page-error" class="text-sm text-error">{@page_error}</p>
        <.button phx-click="next_page" data-role="one-more" variant="primary">One more?</.button>
      </div>

      <section class="flex flex-col gap-2">
        <h2 class="text-sm uppercase tracking-wide opacity-60">In the Room</h2>
        <.roster room={@room} />
      </section>

      <section
        :if={@seat && @room.phase != :waiting}
        class="flex flex-col gap-2 border-t border-base-300 pt-6"
      >
        <h2 class="text-sm uppercase tracking-wide opacity-60">Give a setting</h2>
        <form
          id="give-form"
          data-role="give-form"
          phx-submit="submit_give"
          class="flex flex-col gap-2"
        >
          <div class="flex items-center gap-2">
            <.input
              name="give"
              value={@give_input}
              placeholder="e.g. the world St. Thérèse grew up in"
              class="flex-1"
              autocomplete="off"
            />
            <.button>Give</.button>
          </div>
          <p :if={@give_error} data-role="give-error" class="text-sm text-error">
            {@give_error}
          </p>
          <p
            :if={@room[:give_status] && @room.give_status[:status] == :in_flight}
            data-role="give-status"
            class="text-sm opacity-70"
          >
            The Author is writing Pages for "{@room.give_status.give}"...
          </p>
          <p
            :if={@room[:give_status] && @room.give_status[:status] == :landed}
            data-role="give-status"
            class="text-sm font-medium text-success"
          >
            Pages for "{@room.give_status.give}" have arrived.
          </p>
          <p
            :if={@room[:give_status] && @room.give_status[:status] == :failed}
            data-role="give-status"
            class="text-sm font-medium text-warning"
          >
            The Author couldn't write for "{@room.give_status.give}": {@room.give_status.reason}. Playing on.
          </p>
        </form>
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
