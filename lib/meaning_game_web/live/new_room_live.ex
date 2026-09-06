defmodule MeaningGameWeb.NewRoomLive do
  @moduledoc """
  New Room: open the Room and get a Code to read aloud.

  The Room takes whoever arrives, up to the seat cap.
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
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("create", _params, socket) do
    case Rooms.create(socket.assigns.device_token) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: ~p"/r/#{code}")}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "That Room could not be opened. Try again.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-10 px-6 py-12">
      <h1 class="text-3xl font-semibold">New Room</h1>

      <form phx-submit="create" class="flex flex-col gap-4">
        <p :if={@error} data-role="error" class="text-sm text-error">{@error}</p>
        <.button variant="primary" data-role="open-room">Open the Room</.button>
      </form>

      <.link navigate={~p"/"} class="text-sm underline opacity-70">Back</.link>
    </main>
    """
  end
end
