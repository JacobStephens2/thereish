defmodule ThereishWeb.AdminMediaLive do
  @moduledoc """
  Authenticated gallery of retained Tracks, Vamps, and Masks (ticket 13).
  """
  use ThereishWeb, :live_view

  alias Thereish.Chronicle

  @impl true
  def mount(_params, _session, socket) do
    gallery = Chronicle.gallery()

    {:ok,
     socket
     |> assign(:page_title, "Media")
     |> assign(:robots, "noindex")
     |> assign(:tracks, gallery.tracks)
     |> assign(:vamps, gallery.vamps)
     |> assign(:masks, gallery.masks)
     |> assign(:enlarged_mask, nil)}
  end

  @impl true
  def handle_event("enlarge_mask", %{"url" => url} = params, socket) do
    {:noreply,
     assign(socket, :enlarged_mask, %{
       url: url,
       alt: params["alt"] || "Mask"
     })}
  end

  def handle_event("close_mask", _params, socket) do
    {:noreply, assign(socket, :enlarged_mask, nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.flash_group flash={@flash} />
    <main
      data-role="admin-gallery"
      class="mx-auto flex min-h-screen max-w-xl flex-col gap-8 px-4 py-8"
    >
      <header class="flex items-center justify-between border-b border-base-300 pb-4">
        <h1 class="text-3xl font-bold tracking-tight">Media</h1>
        <.link navigate={~p"/admin"} class="text-sm underline opacity-70 hover:opacity-100">
          ← Admin
        </.link>
      </header>

      <p
        :if={@tracks == [] and @vamps == [] and @masks == []}
        data-role="gallery-empty"
        class="text-sm opacity-70"
      >
        No generated media yet.
      </p>

      <section :if={@tracks != []} data-role="gallery-tracks" class="flex flex-col gap-3">
        <h2 class="text-lg font-bold tracking-tight">Tracks</h2>
        <.audio_card
          :for={track <- @tracks}
          item={track}
          kind="track"
          label="Track"
          name={track.title}
        />
      </section>

      <section :if={@vamps != []} data-role="gallery-vamps" class="flex flex-col gap-3">
        <h2 class="text-lg font-bold tracking-tight">Vamps</h2>
        <.audio_card
          :for={vamp <- @vamps}
          item={vamp}
          kind="vamp"
          label="Vamp"
          name="the short piece"
        />
      </section>

      <section :if={@masks != []} data-role="gallery-masks" class="flex flex-col gap-3">
        <h2 class="text-lg font-bold tracking-tight">Masks</h2>
        <article
          :for={mask <- @masks}
          data-role="gallery-mask"
          class="flex flex-col gap-2 rounded-xl border border-base-300 bg-base-100 p-4"
        >
          <button
            :if={mask.present?}
            type="button"
            phx-click="enlarge_mask"
            phx-value-url={mask.url}
            phx-value-alt="Mask"
            data-role="enlarge-mask"
            data-url={mask.url}
            class="w-fit rounded-md focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            aria-label="Enlarge Mask"
          >
            <img
              src={mask.url}
              alt="Mask"
              class="h-24 w-24 rounded-md border border-base-300 object-cover shadow-sm"
            />
          </button>
          <p :if={!mask.present?} data-role="missing-media" class="text-sm opacity-70">
            Missing
          </p>
          <.provenance associations={mask.associations} />
        </article>
      </section>

      <dialog
        :if={@enlarged_mask}
        open
        data-role="enlarged-mask"
        class="modal"
        phx-window-keydown="close_mask"
        phx-key="Escape"
      >
        <div class="modal-box max-w-3xl p-4">
          <button
            type="button"
            phx-click="close_mask"
            aria-label="Close"
            data-role="close-enlarged-mask"
            class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2"
          >
            ✕
          </button>
          <img
            src={@enlarged_mask.url}
            alt={@enlarged_mask.alt}
            class="mx-auto max-h-[80vh] w-full max-w-full rounded-lg object-contain"
            data-role="enlarged-mask-image"
          />
          <p class="mt-3 text-center text-sm font-medium">{@enlarged_mask.alt}</p>
        </div>
        <form phx-click="close_mask" class="modal-backdrop">
          <button type="button" aria-label="Close">close</button>
        </form>
      </dialog>
    </main>
    """
  end

  attr :item, :map, required: true
  attr :kind, :string, required: true
  attr :label, :string, required: true
  attr :name, :string, default: nil

  defp audio_card(assigns) do
    ~H"""
    <article
      data-role={"gallery-#{@kind}"}
      class="flex flex-col gap-2 rounded-xl border border-base-300 bg-base-100 p-4"
    >
      <div class="flex items-center gap-2">
        <span class="text-xs font-semibold uppercase tracking-wider opacity-60">{@label}</span>
        <span :if={@name} data-role={"#{@kind}-title"} class="text-sm font-medium">{@name}</span>
      </div>

      <audio
        :if={@item.present?}
        data-role={"#{@kind}-player"}
        controls
        src={@item.path}
        preload="none"
        loop={@item.loop}
        class="h-8 w-full"
      >
        Your browser does not support the audio element.
      </audio>

      <p :if={!@item.present?} data-role="missing-media" class="text-sm opacity-70">
        Missing
      </p>

      <.provenance associations={@item.associations} />
    </article>
    """
  end

  attr :associations, :list, required: true

  defp provenance(assigns) do
    ~H"""
    <p :if={@associations == []} data-role="unassociated" class="text-sm opacity-70">
      No associated Page
    </p>
    <div :if={@associations != []} data-role="gallery-provenance" class="flex flex-col gap-1 text-sm">
      <p :for={assoc <- @associations} class="opacity-80">
        <.link
          navigate={~p"/r/#{assoc.room_slug}/chronicle"}
          class="underline hover:opacity-80"
        >
          {assoc.room_slug}
        </.link>
        <span :if={assoc.bookends != []} class="opacity-60">
          · {Enum.join(assoc.bookends, " · ")}
        </span>
      </p>
    </div>
    """
  end
end
