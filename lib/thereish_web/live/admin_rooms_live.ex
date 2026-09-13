defmodule ThereishWeb.AdminRoomsLive do
  @moduledoc """
  Authenticated discovery of every Room (ticket 10).
  """
  use ThereishWeb, :live_view

  alias Thereish.Chronicle

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Rooms")
     |> assign(:robots, "noindex")
     |> assign(:rooms, Chronicle.admin_rooms())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main
      data-role="admin-rooms"
      class="mx-auto flex min-h-screen max-w-xl flex-col gap-8 px-4 py-8"
    >
      <header class="flex items-center justify-between border-b border-base-300 pb-4">
        <h1 class="text-3xl font-bold tracking-tight">Rooms</h1>
        <.link navigate={~p"/admin"} class="text-sm underline opacity-70 hover:opacity-100">
          ← Admin
        </.link>
      </header>

      <p :if={@rooms == []} data-role="rooms-empty" class="text-sm opacity-70">
        No Rooms yet.
      </p>

      <ul :if={@rooms != []} class="flex flex-col gap-3">
        <li
          :for={room <- @rooms}
          data-role="admin-room"
          data-slug={room.slug}
          class="flex flex-col gap-1 rounded-xl border border-base-300 bg-base-100 p-4"
        >
          <div class="flex items-baseline justify-between gap-3">
            <span class="text-lg font-semibold tracking-tight">{room.slug}</span>
            <span class="text-sm opacity-70">
              {page_count_label(room.pages_count)}
            </span>
          </div>
          <p class="text-sm opacity-70">
            Opened {room.opened_at && Calendar.strftime(room.opened_at, "%b %d, %Y")}
          </p>
          <p class="flex gap-3 text-sm">
            <.link
              navigate={~p"/r/#{room.slug}/chronicle"}
              class="underline hover:opacity-80"
            >
              Chronicle
            </.link>
            <.link
              navigate={~p"/admin/timing/#{room.slug}"}
              class="underline hover:opacity-80"
            >
              Timing
            </.link>
          </p>
        </li>
      </ul>
    </main>
    """
  end

  defp page_count_label(1), do: "1 Page"
  defp page_count_label(count), do: "#{count} Pages"
end
