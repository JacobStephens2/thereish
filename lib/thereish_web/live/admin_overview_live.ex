defmodule ThereishWeb.AdminOverviewLive do
  @moduledoc """
  Discoverable access to operator tools (tickets 09 and 10).
  """
  use ThereishWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Admin")
     |> assign(:robots, "noindex")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main
      data-role="admin-overview"
      class="mx-auto flex min-h-screen max-w-xl flex-col gap-8 px-4 py-8"
    >
      <header class="flex items-center justify-between border-b border-base-300 pb-4">
        <h1 class="text-3xl font-bold tracking-tight">Admin</h1>
        <.link
          href={~p"/admin/sign-out"}
          method="delete"
          class="text-sm underline opacity-70 hover:opacity-100"
        >
          Sign out
        </.link>
      </header>

      <ul class="flex flex-col gap-3">
        <li>
          <.link navigate={~p"/spend"} class="text-lg underline hover:opacity-80">Spend</.link>
          <p class="text-sm opacity-70">Operator ledger across all Rooms.</p>
        </li>
        <li>
          <.link navigate={~p"/admin/rooms"} class="text-lg underline hover:opacity-80">
            Rooms
          </.link>
          <p class="text-sm opacity-70">Find a Room and open its Chronicle or timing.</p>
        </li>
        <li>
          <.link navigate={~p"/admin/timing"} class="text-lg underline hover:opacity-80">
            Timing
          </.link>
          <p class="text-sm opacity-70">How long Pages take, with phase breakdowns.</p>
        </li>
        <li>
          <.link navigate={~p"/admin/experiments"} class="text-lg underline hover:opacity-80">
            Experiments
          </.link>
          <p class="text-sm opacity-70">Blinded readouts and deliberate unblinding.</p>
        </li>
        <li>
          <.link navigate={~p"/admin/media"} class="text-lg underline hover:opacity-80">
            Media
          </.link>
          <p class="text-sm opacity-70">Generated Tracks, Vamps, and Masks.</p>
        </li>
        <li>
          <span class="text-lg">Calibration</span>
          <p class="text-sm opacity-70">
            <.link href={~p"/calibration.json"} class="underline hover:opacity-80">JSON</.link>
            <span class="opacity-40">·</span>
            <.link href={~p"/calibration.jsonl"} class="underline hover:opacity-80">JSONL</.link>
            — per-Room Markdown and calibration exports sit on Spend.
          </p>
        </li>
      </ul>
    </main>
    """
  end
end
