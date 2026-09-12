defmodule ThereishWeb.AdminOverviewLive do
  @moduledoc """
  Discoverable access to existing operator tools (ticket 09).

  Later Room, timing, and media slices add their destinations here; this page
  does not invent placeholder links for them.
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
          <.link navigate={~p"/admin/experiments"} class="text-lg underline hover:opacity-80">
            Experiments
          </.link>
          <p class="text-sm opacity-70">Blinded readouts and deliberate unblinding.</p>
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
