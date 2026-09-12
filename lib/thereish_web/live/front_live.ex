defmodule ThereishWeb.FrontLive do
  @moduledoc """
  The door: a box for a Code, a New Room button, and the way back into every
  Room this phone already holds a Seat in.

  The bare URL used to be the couch itself, which worked while there was one
  Room and one couple. A friend at a table has been told one thing — a word —
  and this is the screen that asks for it and nothing else.

  Nothing here creates a Room. A Code that no Room has is said so plainly,
  because a Room conjured out of a typo is a Room the rest of the table cannot
  find.

  A Room on the list can be hidden for this browser. That drops the shortcut,
  not the Seat: the Code and a saved link still open the same Seat.
  """
  use ThereishWeb, :live_view

  alias Thereish.Rooms
  alias Thereish.Rooms.Code
  alias ThereishWeb.DeviceToken

  @impl true
  def mount(_params, session, socket) do
    device_token = DeviceToken.from_session(session)

    {:ok,
     socket
     |> assign(:code, "")
     |> assign(:error, nil)
     |> assign(:device_token, device_token)
     |> assign(:rooms, Rooms.listed_for_device(device_token))}
  end

  @impl true
  def handle_event("open", %{"code" => typed}, socket) do
    # Asking the Room interface rather than the Code's shape, because a word
    # that is spelled like a Code and belongs to nobody is exactly the mistake
    # this page exists to catch.
    case Rooms.ensure_started(typed) do
      {:ok, code, _pid} ->
        {:noreply, push_navigate(socket, to: ~p"/r/#{code}")}

      {:error, _reason} ->
        {:noreply, assign(socket, code: typed, error: no_such_room(typed))}
    end
  end

  def handle_event("hide", %{"code" => code}, socket) do
    _ = Rooms.hide(code, socket.assigns.device_token)

    {:noreply, assign(socket, rooms: Rooms.listed_for_device(socket.assigns.device_token))}
  end

  defp no_such_room(typed) do
    typed = typed |> to_string() |> String.trim()

    cond do
      typed == "" -> "Type the Code you were told."
      String.length(typed) > 40 -> "No Room has that Code."
      true -> "No Room has the Code #{Code.shout(typed)}."
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-10 px-6 py-12">
      <h1 class="text-3xl font-semibold">Thereish</h1>

      <form phx-submit="open" class="flex flex-col gap-2">
        <.input
          name="code"
          value={@code}
          label="Code"
          placeholder="the word you were told"
          autocomplete="off"
          autocapitalize="characters"
          autofocus
        />
        <p :if={@error} data-role="error" class="text-sm text-error">{@error}</p>
        <.button variant="primary">Open the Room</.button>
      </form>

      <div class="flex flex-col gap-2">
        <p class="text-sm uppercase tracking-wide opacity-60">Nobody told you a Code?</p>
        <.button navigate={~p"/new"} data-role="new-room">New Room</.button>
      </div>

      <section :if={@rooms != []} class="flex flex-col gap-3 border-t border-base-300 pt-6">
        <h2 class="text-sm uppercase tracking-wide opacity-60">Your Rooms</h2>
        <ul class="flex flex-col gap-2">
          <li :for={%{room: room, seat: seat} <- @rooms} class="flex flex-col gap-1">
            <div class="flex items-baseline justify-between gap-3">
              <.link
                navigate={~p"/r/#{room.slug}"}
                data-role="rejoin"
                data-code={room.slug}
                class="flex items-baseline gap-3 text-lg underline"
              >
                <span class="font-mono font-semibold tracking-widest">{Code.shout(room.slug)}</span>
                <span class="text-sm opacity-60">as {seat.name}</span>
              </.link>
              <button
                type="button"
                phx-click="hide"
                phx-value-code={room.slug}
                data-role="hide"
                data-code={room.slug}
                class="shrink-0 text-sm opacity-60 underline"
              >
                Hide
              </button>
            </div>
            <p :if={room.quip} data-role="rejoin-quip" class="text-sm italic opacity-70">
              {room.quip}
            </p>
          </li>
        </ul>
      </section>
    </main>
    """
  end
end
