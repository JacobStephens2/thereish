defmodule ThereishWeb.SpendLive do
  @moduledoc """
  Operator spend page across all Rooms by role and model (ticket 09).

  Totals every Room by role and by model with call counts, read from the
  Chronicle's rows by `Thereish.Chronicle.Spend` (never stored).
  """
  use ThereishWeb, :live_view

  alias Thereish.Chronicle.Spend
  alias Thereish.Rooms

  @impl true
  def mount(_params, _session, socket) do
    spend = Spend.all()
    in_play_count = Rooms.in_play_count()

    {:ok,
     socket
     |> assign(:page_title, "Spend")
     |> assign(:robots, "noindex")
     |> assign(:spend, spend)
     |> assign(:in_play_count, in_play_count)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto flex min-h-screen max-w-4xl flex-col gap-8 px-4 py-8">
      <header class="flex flex-col gap-2 border-b border-base-300 pb-4">
        <div class="flex items-center justify-between">
          <h1 data-role="spend-heading" class="text-3xl font-bold tracking-tight">Spend</h1>
          <.link
            navigate={~p"/admin"}
            class="text-sm font-medium underline opacity-70 hover:opacity-100"
          >
            ← Admin
          </.link>
        </div>
        <p class="text-sm opacity-60">
          Operator ledger across all Rooms — computed from rows, never stored.
        </p>
      </header>

      <!-- Totals Banner -->
      <section
        data-role="spend-totals"
        class="grid grid-cols-1 gap-4 sm:grid-cols-3 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm"
      >
        <div class="flex flex-col gap-1">
          <span class="text-xs font-semibold uppercase tracking-wider opacity-60">Total Spend</span>
          <span class="text-2xl font-bold font-mono text-primary">
            {Spend.format_usd(@spend.total_usd)}
          </span>
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-xs font-semibold uppercase tracking-wider opacity-60">Total Calls</span>
          <span class="text-2xl font-bold font-mono">
            {@spend.calls_count} {if @spend.calls_count == 1, do: "call", else: "calls"}
          </span>
        </div>
        <div class="flex flex-col gap-1">
          <span class="text-xs font-semibold uppercase tracking-wider opacity-60">Unpriced Calls</span>
          <span class="text-2xl font-bold font-mono opacity-80">
            {@spend.unpriced_count} unpriced
          </span>
        </div>
      </section>

      <p
        :if={@in_play_count > 0}
        data-role="in-play-count"
        class="font-mono text-sm opacity-75 -mt-4"
      >
        {Rooms.in_play_sentence(@in_play_count)}
      </p>

      <!-- Spend by Role -->
      <section data-role="spend-by-role" class="flex flex-col gap-3">
        <h2 class="text-lg font-bold tracking-tight">By Role</h2>
        <div class="overflow-x-auto rounded-lg border border-base-300 bg-base-100">
          <table class="table w-full text-left text-sm">
            <thead class="border-b border-base-200 text-xs uppercase opacity-70">
              <tr>
                <th class="py-3 px-4">Role</th>
                <th class="py-3 px-4">Spend</th>
                <th class="py-3 px-4">Calls</th>
                <th class="py-3 px-4">Unpriced</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-200 font-mono text-xs">
              <tr :for={{role_name, role_key} <- Spend.roles()}>
                <% role_data = @spend.by_role[role_key] %>
                <td class="py-2.5 px-4 font-sans font-medium text-sm">{role_name}</td>
                <td class="py-2.5 px-4">{Spend.format_usd(role_data.total_usd)}</td>
                <td class="py-2.5 px-4">{role_data.calls_count}</td>
                <td class="py-2.5 px-4">{role_data.unpriced_count}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Spend by Role and Model -->
      <section data-role="spend-by-role-and-model" class="flex flex-col gap-3">
        <h2 class="text-lg font-bold tracking-tight">By Role and Model</h2>
        <div class="overflow-x-auto rounded-lg border border-base-300 bg-base-100">
          <table class="table w-full text-left text-sm">
            <thead class="border-b border-base-200 text-xs uppercase opacity-70">
              <tr>
                <th class="py-3 px-4">Role</th>
                <th class="py-3 px-4">Model</th>
                <th class="py-3 px-4">Spend</th>
                <th class="py-3 px-4">Calls</th>
                <th class="py-3 px-4">Unpriced</th>
              </tr>
            </thead>
            <tbody class="divide-y border-base-200 font-mono text-xs">
              <tr :if={@spend.calls_count == 0}>
                <td colspan="5" class="py-4 px-4 font-sans text-center opacity-60">
                  No model calls recorded yet.
                </td>
              </tr>
              <%= for {role_name, role_key} <- Spend.roles() do %>
                <% role_data = @spend.by_role[role_key] %>
                <%= for {model, stats} <- Enum.sort_by(role_data.by_model, &elem(&1, 0)) do %>
                  <tr>
                    <td class="py-2.5 px-4 font-sans font-medium text-sm">{role_name}</td>
                    <td class="py-2.5 px-4 font-sans font-medium text-sm">{model}</td>
                    <td class="py-2.5 px-4">{Spend.format_usd(stats.total_usd)}</td>
                    <td class="py-2.5 px-4">{stats.calls_count}</td>
                    <td class="py-2.5 px-4">{stats.unpriced_count}</td>
                  </tr>
                <% end %>
              <% end %>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Spend by Model -->
      <section data-role="spend-by-model" class="flex flex-col gap-3">
        <h2 class="text-lg font-bold tracking-tight">By Model</h2>
        <div class="overflow-x-auto rounded-lg border border-base-300 bg-base-100">
          <table class="table w-full text-left text-sm">
            <thead class="border-b border-base-200 text-xs uppercase opacity-70">
              <tr>
                <th class="py-3 px-4">Model</th>
                <th class="py-3 px-4">Spend</th>
                <th class="py-3 px-4">Calls</th>
                <th class="py-3 px-4">Unpriced</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-200 font-mono text-xs">
              <tr :if={@spend.by_model == %{}}>
                <td colspan="4" class="py-4 px-4 font-sans text-center opacity-60">
                  No model calls recorded yet.
                </td>
              </tr>
              <tr :for={{model, stats} <- Enum.sort_by(@spend.by_model, &elem(&1, 0))}>
                <td class="py-2.5 px-4 font-sans font-medium text-sm">{model}</td>
                <td class="py-2.5 px-4">{Spend.format_usd(stats.total_usd)}</td>
                <td class="py-2.5 px-4">{stats.calls_count}</td>
                <td class="py-2.5 px-4">{stats.unpriced_count}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Per-Room Breakdown -->
      <section data-role="spend-by-room" class="flex flex-col gap-3 pb-8">
        <h2 class="text-lg font-bold tracking-tight">Rooms</h2>
        <div
          :if={@spend.rooms == []}
          class="rounded-lg border border-base-300 bg-base-100 p-6 text-center text-sm opacity-60"
        >
          No rooms played yet.
        </div>
        <div
          :if={@spend.rooms != []}
          class="overflow-x-auto rounded-lg border border-base-300 bg-base-100"
        >
          <table class="table w-full text-left text-sm">
            <thead class="border-b border-base-200 text-xs uppercase opacity-70">
              <tr>
                <th class="py-3 px-4">Room</th>
                <th class="py-3 px-4">Opened</th>
                <th class="py-3 px-4">Total</th>
                <th class="py-3 px-4">Calls</th>
                <th :for={{role_name, _role_key} <- Spend.roles()} class="py-3 px-4">
                  {role_name}
                </th>
                <th class="py-3 px-4">Unpriced</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-base-200 text-xs">
              <tr :for={r <- @spend.rooms}>
                <td class="py-2.5 px-4 font-medium">
                  <.link navigate={~p"/r/#{r.slug}/chronicle"} class="underline hover:opacity-80">
                    {r.slug}
                  </.link>
                  <span class="opacity-40">·</span>
                  <a
                    href={~p"/r/#{r.slug}/chronicle.md"}
                    class="text-xs underline opacity-70 hover:opacity-100"
                  >
                    Markdown
                  </a>
                  <span class="opacity-40">·</span>
                  <a
                    href={~p"/r/#{r.slug}/calibration.json"}
                    class="text-xs underline opacity-70 hover:opacity-100"
                  >
                    Calibration
                  </a>
                </td>
                <td
                  class="py-2.5 px-4 font-mono whitespace-nowrap opacity-80"
                  data-role="room-opened"
                >
                  {r.opened_at && Calendar.strftime(r.opened_at, "%b %d, %Y")}
                </td>
                <td class="py-2.5 px-4 font-mono font-semibold">
                  {Spend.format_usd(r.total_usd)}
                </td>
                <td class="py-2.5 px-4 font-mono">{r.calls_count}</td>
                <td
                  :for={{_role_name, role_key} <- Spend.roles()}
                  class="py-2.5 px-4 font-mono text-opacity-80"
                >
                  {Spend.format_usd(r.by_role[role_key].total_usd)}
                </td>
                <td class="py-2.5 px-4 font-mono">{r.unpriced_count}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </main>
    """
  end
end
