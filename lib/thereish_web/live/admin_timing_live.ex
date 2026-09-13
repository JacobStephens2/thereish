defmodule ThereishWeb.AdminTimingLive do
  @moduledoc """
  Authenticated Page duration readout (ticket 10).
  """
  use ThereishWeb, :live_view

  alias Thereish.Chronicle
  alias Thereish.Chronicle.Timing

  @impl true
  def mount(params, _session, socket) do
    slug = params["slug"]
    timings = if slug, do: Chronicle.page_timings(slug), else: Chronicle.page_timings()

    {:ok,
     socket
     |> assign(:page_title, if(slug, do: "Timing · #{slug}", else: "Timing"))
     |> assign(:robots, "noindex")
     |> assign(:slug, slug)
     |> assign(:timings, timings)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main
      data-role="admin-timing"
      class="mx-auto flex min-h-screen max-w-xl flex-col gap-8 px-4 py-8"
    >
      <header class="flex items-center justify-between border-b border-base-300 pb-4">
        <h1 class="text-3xl font-bold tracking-tight">
          {if @slug, do: "Timing · #{@slug}", else: "Timing"}
        </h1>
        <.link navigate={~p"/admin"} class="text-sm underline opacity-70 hover:opacity-100">
          ← Admin
        </.link>
      </header>

      <p :if={@timings == []} class="text-sm opacity-70">No Pages recorded yet.</p>

      <article
        :for={page <- @timings}
        data-role="page-timing"
        data-kind={page.kind}
        data-outcome={page.outcome |> to_string() |> String.replace("_", "-")}
        data-total-ms={page.total_ms}
        class="flex flex-col gap-3 rounded-xl border border-base-300 bg-base-100 p-4"
      >
        <div class="flex items-baseline justify-between gap-3">
          <span class="font-semibold tracking-tight">
            {page.room_slug}
          </span>
          <span class="text-sm opacity-70">{Timing.outcome_label(page)}</span>
        </div>

        <p class="text-sm">
          <span class="font-medium">{total_label(page)}</span>
          <span :if={page.kind == :estimate} class="opacity-70"> (estimate)</span>
        </p>

        <dl class="grid grid-cols-1 gap-1 text-sm">
          <.phase name={:give_entry} label="Give entry" phase={page.phases.give_entry} />
          <.phase name={:generation} label="Generation" phase={page.phases.generation} />
          <.phase
            name={:bridge_writing}
            label="Bridge writing"
            phase={page.phases.bridge_writing}
          />
          <.phase name={:assayer_beat} label="Assayer / Beat" phase={page.phases.assayer_beat} />
          <.phase
            name={:reveal_pauses}
            label="Reveal pauses"
            phase={page.phases.reveal_pauses}
          />
        </dl>
      </article>
    </main>
    """
  end

  attr :name, :atom, required: true
  attr :label, :string, required: true
  attr :phase, :map, required: true

  defp phase(assigns) do
    ~H"""
    <div
      data-phase={@name |> to_string() |> String.replace("_", "-")}
      data-kind={@phase.kind}
      data-ms={@phase.ms}
      class="flex items-baseline justify-between gap-3"
    >
      <dt class="opacity-70">{@label}</dt>
      <dd>
        {if @phase.kind == :unavailable, do: "unavailable", else: Timing.format_ms(@phase.ms)}
      </dd>
    </div>
    """
  end

  defp total_label(%{kind: :estimate, total_ms: ms}), do: "~#{Timing.format_ms(ms)}"
  defp total_label(%{total_ms: ms}), do: Timing.format_ms(ms)
end
