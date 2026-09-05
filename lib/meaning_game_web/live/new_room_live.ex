defmodule MeaningGameWeb.NewRoomLive do
  @moduledoc """
  New Room: how many players, and then a Code to read aloud.

  The one question is the size of the table, because that is the one thing the
  Room cannot work out for itself and cannot change afterwards. Everything else
  — the Code, the Seats, who is who — happens on the other side of the button.

  Creating a Room gives the creator nothing to manage: it lands them in the Room
  as a phone with no Seat yet, and they type a name like everybody else.
  """
  use MeaningGameWeb, :live_view

  alias MeaningGame.Rooms
  alias MeaningGameWeb.DeviceToken

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:device_token, DeviceToken.from_session(session))
     |> assign(:players, Rooms.default_seat_limit())
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("create", %{"players" => players}, socket) do
    case Rooms.create(to_count(players), socket.assigns.device_token) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: ~p"/r/#{code}")}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "That Room could not be opened. Try again.")}
    end
  end

  defp to_count(players) do
    case Integer.parse(to_string(players)) do
      {count, ""} -> count
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-10 px-6 py-12">
      <h1 class="text-3xl font-semibold">New Room</h1>

      <form phx-submit="create" class="flex flex-col gap-4">
        <.input
          type="select"
          name="players"
          value={@players}
          label="How many players?"
          options={Enum.to_list(Rooms.seat_counts())}
        />
        <p :if={@error} data-role="error" class="text-sm text-error">{@error}</p>
        <.button variant="primary" data-role="open-room">Open the Room</.button>
      </form>

      <.link navigate={~p"/"} class="text-sm underline opacity-70">Back</.link>
    </main>
    """
  end
end
