defmodule ThereishWeb.NewRoomLive do
  @moduledoc """
  New Room: open the Room and get a Code to read aloud.

  The Room takes whoever arrives, up to the seat cap.
  Creating a Room gives the creator nothing to manage: it lands them in the Room
  as a phone with no Seat yet, and they type a name like everybody else.
  """
  use ThereishWeb, :live_view

  alias Thereish.Rooms
  alias ThereishWeb.DeviceToken

  @impl true
  def mount(_params, session, socket) do
    {:ok,
     socket
     |> assign(:device_token, DeviceToken.from_session(session))
     |> assign(:remote_address, remote_address(socket, session))
     |> assign(:error, nil)}
  end

  @impl true
  def handle_event("create", _params, socket) do
    opts =
      case socket.assigns[:remote_address] do
        nil -> []
        address -> [address: address]
      end

    case Rooms.create(socket.assigns.device_token, opts) do
      {:ok, code} ->
        {:noreply, push_navigate(socket, to: ~p"/r/#{code}")}

      {:error, :rate_limited} ->
        {:noreply, assign(socket, :error, "Give it a minute")}

      {:error, _reason} ->
        {:noreply, assign(socket, :error, "That Room could not be opened. Try again.")}
    end
  end

  defp remote_address(socket, session) do
    case get_connect_info(socket, :peer_data) do
      %{address: address} when is_tuple(address) ->
        address |> :inet.ntoa() |> to_string()

      _ ->
        Map.get(session, "remote_ip")
    end
  rescue
    _ -> Map.get(session, "remote_ip")
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

      <Layouts.made_by />
    </main>
    """
  end
end
