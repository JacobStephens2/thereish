defmodule ThereishWeb.ChronicleLive do
  @moduledoc """
  The Chronicle as a book read on a phone (ticket 08).

  Reads the Chronicle in reverse chronological order: every Page, every attempt,
  both Bridges, the grade, the reasoning, and any overrule. Players can correct
  an entry, and the correction is recorded as another append-only event rather
  than mutating past Pages (design law 5, ADR-0003).

  Every view is computed from the event log.
  """
  use ThereishWeb, :live_view

  import ThereishWeb.RoomComponents

  alias Thereish.Chronicle
  alias Thereish.Repo
  alias Thereish.Rooms
  alias Thereish.Rooms.Room
  alias ThereishWeb.DeviceToken

  @impl true
  def mount(params, session, socket) do
    slug = Rooms.open!(params["slug"])
    device_token = DeviceToken.from_session(session)
    room = Repo.get_by!(Room, slug: slug)
    seat = seat_for_device(slug, device_token)

    if connected?(socket), do: Rooms.subscribe(slug)

    {:ok,
     socket
     |> assign(:slug, slug)
     |> assign(:room, room)
     |> assign(:seat, seat)
     |> assign(:device_token, device_token)
     |> assign(:correcting_page_id, nil)
     |> assign(:correction_params, default_correction_params())
     |> assign(:enlarged_mask, nil)
     |> load_pages()}
  end

  @impl true
  def handle_event("open_correction", %{"page-id" => page_id}, socket) do
    {:noreply,
     assign(socket, correcting_page_id: page_id, correction_params: default_correction_params())}
  end

  def handle_event("cancel_correction", _params, socket) do
    {:noreply,
     assign(socket, correcting_page_id: nil, correction_params: default_correction_params())}
  end

  def handle_event("record_correction", %{"correction" => params}, socket) do
    page_id = socket.assigns.correcting_page_id
    seat_id = socket.assigns.seat && socket.assigns.seat.id

    attempt_number =
      case params["attempt_number"] do
        nil ->
          nil

        "" ->
          nil

        num when is_binary(num) ->
          case Integer.parse(num) do
            {val, _} -> val
            :error -> nil
          end

        num when is_integer(num) ->
          num
      end

    attrs = %{
      page_id: page_id,
      seat_id: seat_id,
      attempt_number: attempt_number,
      target: params["target"] || "bridge",
      original_value: blank_to_nil(params["original_value"]),
      corrected_value: params["corrected_value"],
      note: blank_to_nil(params["note"])
    }

    case Chronicle.record_correction(socket.assigns.room.id, attrs) do
      {:ok, _correction} ->
        Phoenix.PubSub.broadcast(Thereish.PubSub, "room:#{socket.assigns.slug}", :room_changed)

        {:noreply,
         socket
         |> assign(correcting_page_id: nil, correction_params: default_correction_params())
         |> load_pages()}

      {:error, _changeset} ->
        {:noreply, assign(socket, :correction_params, params)}
    end
  end

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
  def handle_info(:room_changed, socket), do: {:noreply, load_pages(socket)}
  def handle_info(:chronicle_changed, socket), do: {:noreply, load_pages(socket)}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket),
    do: {:noreply, socket}

  defp load_pages(socket) do
    assign(socket, :pages, Chronicle.book(socket.assigns.room.id))
  end

  defp default_correction_params do
    %{
      "attempt_number" => "",
      "target" => "bridge",
      "original_value" => "",
      "corrected_value" => "",
      "note" => ""
    }
  end

  defp seat_for_device(slug, device_token) do
    if device_token do
      case Rooms.rejoin(slug, device_token) do
        {:ok, seat} -> seat
        :error -> nil
      end
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(str) when is_binary(str) do
    trimmed = String.trim(str)
    if trimmed == "", do: nil, else: trimmed
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main class="mx-auto flex min-h-screen max-w-xl flex-col gap-6 px-4 py-8">
      <header class="flex flex-col gap-2 border-b border-base-300 pb-4">
        <div class="flex items-center justify-between">
          <div class="flex items-baseline gap-3">
            <.link
              navigate={~p"/"}
              class="text-xl font-semibold tracking-tight hover:opacity-80"
            >
              Thereish
            </.link>
            <span class="opacity-40">·</span>
            <h1 class="text-3xl font-bold tracking-tight">The Chronicle</h1>
          </div>
          <.link
            navigate={room_path(@slug)}
            class="text-sm font-medium underline opacity-70 hover:opacity-100"
          >
            ← Back to Room
          </.link>
        </div>
        <div class="flex items-center justify-between text-sm opacity-60">
          <span>Room: {@slug}</span>
        </div>
      </header>

      <div
        :if={@pages == []}
        data-role="empty-chronicle"
        class="rounded-xl border border-dashed border-base-300 p-8 text-center opacity-60"
      >
        <p class="text-lg">The Chronicle is empty.</p>
        <p class="mt-1 text-sm">Play a Page to begin your story.</p>
      </div>

      <div :if={@pages != []} class="flex flex-col gap-8">
        <article
          :for={page <- @pages}
          data-role="chronicle-page"
          data-page-id={page.id}
          class="flex flex-col gap-4 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm"
        >
          <!-- Page Header -->
          <div class="flex flex-wrap items-start justify-between gap-2 border-b border-base-200 pb-3">
            <div>
              <div class="flex flex-wrap items-center gap-2">
                <h2 class="text-2xl font-bold tracking-tight">
                  {Enum.join(page.bookends, " · ")}
                </h2>
                <span
                  :if={page[:full_table] == true}
                  data-role="page-rule"
                  class="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary"
                >
                  Full table
                </span>
                <span
                  :if={page[:full_table] == false}
                  data-role="page-rule"
                  class="rounded-full bg-base-300 px-2.5 py-0.5 text-xs font-semibold opacity-80"
                >
                  Two Bookends
                </span>
                <span
                  :for={g <- page[:gives] || []}
                  data-role="give-tag"
                  class="inline-flex items-center gap-1.5 rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary"
                >
                  <.enlargeable_mask
                    :if={is_map(g[:mask]) and (g.mask[:url] || g.mask["url"])}
                    url={g.mask[:url] || g.mask["url"]}
                    alt={"Mask for " <> g.seat_name}
                    seat_id={g.seat_id}
                    class="h-4 w-4 rounded-full object-cover"
                  />
                  <span>Give ({g.seat_name}): {g.text}</span>
                </span>
                <span
                  :if={(page[:gives] == nil or page[:gives] == []) and page[:give]}
                  data-role="give-tag"
                  class="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary"
                >
                  Give: {page.give}
                </span>
              </div>
              <p class="text-xs opacity-50">
                {page.closed_at && Calendar.strftime(page.closed_at, "%b %d, %Y at %I:%M %p")}
              </p>
            </div>
            <div>
              <span
                :if={page.melded}
                class="rounded-full bg-success/20 px-3 py-1 text-xs font-semibold text-success"
              >
                Meld {page.closeness}
              </span>
              <span
                :if={!page.melded}
                class="rounded-full bg-base-200 px-3 py-1 text-xs font-semibold opacity-70"
              >
                Unmelded
              </span>
            </div>
          </div>

          <!-- Masks if present -->
          <div
            :if={
              is_map(page[:masks]) and map_size(page.masks) > 0 and
                Enum.any?(page.masks, fn {_, m} -> is_map(m) and (m[:url] || m["url"]) end)
            }
            data-role="page-masks"
            class="flex items-center gap-3 rounded-lg bg-base-200/50 p-3"
          >
            <span class="text-xs font-semibold uppercase tracking-wider opacity-60">Masks</span>
            <div class="flex flex-wrap items-center gap-2">
              <.enlargeable_mask
                :for={{seat_id, mask} <- page.masks}
                :if={is_map(mask) and (mask[:url] || mask["url"])}
                url={mask[:url] || mask["url"]}
                alt="Mask"
                seat_id={seat_id}
                class="h-8 w-8 rounded-md border border-base-300 object-cover shadow-sm"
              />
            </div>
          </div>

          <.chronicle_audio
            :if={track = page_track(page)}
            role="track"
            label="Track"
            name={track.title}
            name_role="track-title"
            src={track.path}
          />

          <.chronicle_audio
            :if={vamp = page_vamp(page)}
            role="vamp"
            label="Vamp"
            name="the short piece"
            name_role="vamp-label"
            src={vamp.path}
            loop={vamp.loop}
          />

          <!-- Attempts list -->
          <div class="flex flex-col gap-4">
            <section
              :for={attempt <- page.attempts}
              data-role="attempt"
              data-attempt-number={attempt.number}
              class="flex flex-col gap-2 rounded-lg bg-base-200/50 p-3"
            >
              <div class="flex items-center justify-between text-xs uppercase tracking-wider opacity-60">
                <span>Attempt {attempt.number}</span>
              </div>

              <.bookends
                room={%{bookend_chips: attempt[:bookend_chips] || []}}
                mode={:phone}
              />

              <p
                :for={chip <- attempt[:bookend_chips] || []}
                :if={chip[:give]}
                data-role="bookend-give"
                class="text-xs opacity-70"
              >
                {chip.word} from {chip.seat_name}'s {chip.give}
              </p>

              <!-- Bridges -->
              <div class="flex flex-wrap items-center gap-3 text-base">
                <div :for={b <- attempt.bridges} class="flex items-center gap-1.5">
                  <span class="text-sm font-semibold opacity-70">{b.seat_name}:</span>
                  <span class="font-medium underline decoration-primary/40 decoration-2">{b.bridge}</span>
                  <span
                    :if={b[:corrected?] && b[:original_bridge]}
                    class="text-xs line-through opacity-50"
                  >
                    ({b.original_bridge})
                  </span>
                </div>
              </div>

              <!-- Verdict -->
              <div
                :for={v <- attempt.verdicts}
                class="mt-1 flex flex-col gap-1 border-t border-base-200/80 pt-2 text-sm"
              >
                <div class="flex items-center gap-2">
                  <span :if={v.graded} class="font-bold">
                    {v.closeness} / 100
                  </span>
                  <span
                    :if={v.band}
                    class="rounded bg-base-300 px-1.5 py-0.5 text-xs uppercase tracking-wide opacity-80"
                  >
                    {v.band}
                  </span>
                  <span :if={!v.graded} class="italic opacity-60">
                    Ungraded
                  </span>
                </div>
                <p :if={v.reasoning} class="italic opacity-80">"{v.reasoning}"</p>
                <p :if={v.quip} class="text-xs font-medium opacity-90">{v.quip}</p>
              </div>

              <p
                :if={attempt[:carried] && attempt.carried != []}
                data-role="carried-words"
                class="text-xs opacity-70"
              >
                Carried: <span class="font-medium">{join_and(attempt.carried)}</span>
              </p>

              <!-- Fairness taps on this attempt -->
              <div
                :if={attempt[:fairness_taps] && attempt.fairness_taps != []}
                data-role="fairness-taps"
                class="mt-1 flex flex-wrap items-center gap-1.5 text-xs"
              >
                <span class="text-[10px] font-semibold uppercase tracking-wider opacity-60">
                  Fairness:
                </span>
                <span
                  :for={t <- attempt.fairness_taps}
                  data-role="fairness-tap-entry"
                  class={[
                    "rounded px-1.5 py-0.5 text-xs font-medium",
                    case t.label do
                      "fair" -> "bg-success/15 text-success font-semibold"
                      "too_kind" -> "bg-info/15 text-info font-semibold"
                      "too_harsh" -> "bg-warning/15 text-warning font-semibold"
                      _ -> "bg-base-300"
                    end
                  ]}
                >
                  {t.seat_name}: {human_label(t.label)}
                </span>
              </div>

              <!-- Overrule on this attempt -->
              <div
                :for={o <- attempt.overrules}
                data-role="overrule"
                class="mt-1 rounded border border-warning/40 bg-warning/10 p-2.5 text-xs text-warning-content"
              >
                <div class="flex items-center justify-between font-semibold">
                  <span>Overruled jointly by {o.proposer_name} and the couple</span>
                  <span>{o.machine_closeness} → {o.couple_closeness} / 100</span>
                </div>
                <p class="mt-1 italic">"{o.couple_reasoning}"</p>
              </div>
            </section>
          </div>

          <!-- Page Overrules not attached to an attempt -->
          <div
            :for={o <- page.overrules -- Enum.flat_map(page.attempts, & &1.overrules)}
            data-role="overrule"
            class="rounded border border-warning/40 bg-warning/10 p-2.5 text-xs text-warning-content"
          >
            <div class="flex items-center justify-between font-semibold">
              <span>Overruled jointly by {o.proposer_name} and the couple</span>
              <span>{o.machine_closeness} → {o.couple_closeness} / 100</span>
            </div>
            <p class="mt-1 italic">"{o.couple_reasoning}"</p>
          </div>

          <!-- What the Scribe wrote about this Page -->
          <div
            :if={page.recap}
            data-role="recap"
            class="flex flex-col gap-1.5 rounded border-l-2 border-primary/40 bg-base-200/40 px-3 py-2.5"
          >
            <span class="text-xs uppercase tracking-wider opacity-50">The Scribe</span>
            <p data-role="recap-prose" class="text-sm leading-relaxed">{page.recap.recap}</p>
            <p
              :if={page.recap.callback}
              data-role="recap-callback"
              class="text-sm italic leading-relaxed opacity-80"
            >
              {page.recap.callback}
            </p>
            <p :if={page.recap.corrected?} class="text-xs opacity-50">
              Corrected by the players.
            </p>
          </div>

          <!-- Corrections Section -->
          <div
            :if={page.corrections != []}
            data-role="corrections"
            class="flex flex-col gap-1.5 border-t border-base-200 pt-2"
          >
            <span class="text-xs uppercase tracking-wider opacity-50">Corrections</span>
            <div
              :for={c <- page.corrections}
              data-role="correction"
              class="rounded bg-base-200/60 px-3 py-2 text-xs"
            >
              <p>
                <span class="font-semibold">{c.author_name}</span>
                corrected {c.target}
                <span :if={c.original_value}>from "<span class="line-through">{c.original_value}</span>"</span>
                to "<span class="font-bold">{c.corrected_value}</span>"
                <span :if={c.note} class="italic opacity-80">— {c.note}</span>
              </p>
            </div>
          </div>

          <!-- Correction Toggle / Form -->
          <div class="mt-2 flex flex-col gap-2 border-t border-base-200 pt-3">
            <div :if={@correcting_page_id != page.id} class="flex justify-end">
              <button
                type="button"
                data-role="open-correction"
                data-page-id={page.id}
                phx-click="open_correction"
                phx-value-page-id={page.id}
                class="text-xs underline opacity-60 hover:opacity-100"
              >
                Correct entry
              </button>
            </div>

            <!-- Correction Form -->
            <form
              :if={@correcting_page_id == page.id}
              data-role="correction-form"
              phx-submit="record_correction"
              class="flex flex-col gap-3 rounded-lg bg-base-200/80 p-3 text-sm"
            >
              <span class="font-semibold">Correct this entry</span>

              <div :if={page.attempts != []} class="flex flex-col gap-1">
                <label class="text-xs opacity-70">Attempt (optional)</label>
                <select
                  name="correction[attempt_number]"
                  class="select select-sm w-full rounded border border-base-300 bg-base-100"
                >
                  <option value="" selected={@correction_params["attempt_number"] in ["", nil]}>
                    Whole page
                  </option>
                  <option
                    :for={att <- page.attempts}
                    value={att.number}
                    selected={
                      to_string(att.number) == to_string(@correction_params["attempt_number"])
                    }
                  >
                    Attempt {att.number}
                  </option>
                </select>
              </div>

              <div class="flex flex-col gap-1">
                <label class="text-xs opacity-70">What are you correcting?</label>
                <select
                  name="correction[target]"
                  class="select select-sm w-full rounded border border-base-300 bg-base-100"
                >
                  <option value="recap" selected={@correction_params["target"] == "recap"}>
                    Recap
                  </option>
                  <option value="bridge" selected={@correction_params["target"] == "bridge"}>
                    Bridge
                  </option>
                  <option value="note" selected={@correction_params["target"] == "note"}>Note</option>
                </select>
              </div>

              <div class="flex flex-col gap-1">
                <label class="text-xs opacity-70">Original value (optional)</label>
                <input
                  type="text"
                  name="correction[original_value]"
                  value={@correction_params["original_value"]}
                  placeholder="e.g. what was mistyped"
                  class="input input-sm w-full rounded border border-base-300 bg-base-100"
                />
              </div>

              <div class="flex flex-col gap-1">
                <label class="text-xs font-medium">Correction / Fix</label>
                <input
                  type="text"
                  name="correction[corrected_value]"
                  value={@correction_params["corrected_value"]}
                  required
                  placeholder="e.g. what it should be"
                  class="input input-sm w-full rounded border border-base-300 bg-base-100"
                />
              </div>

              <div class="flex flex-col gap-1">
                <label class="text-xs opacity-70">Reason or note (optional)</label>
                <input
                  type="text"
                  name="correction[note]"
                  value={@correction_params["note"]}
                  placeholder="e.g. autocorrect error"
                  class="input input-sm w-full rounded border border-base-300 bg-base-100"
                />
              </div>

              <div class="flex items-center justify-end gap-2 pt-1">
                <button
                  type="button"
                  data-role="cancel-correction"
                  phx-click="cancel_correction"
                  class="btn btn-ghost btn-xs"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  data-role="submit-correction"
                  class="btn btn-primary btn-xs"
                >
                  Record correction
                </button>
              </div>
            </form>
          </div>
        </article>
      </div>

      <Layouts.made_by />

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

  defp room_path(slug), do: ~p"/r/#{slug}"

  defp human_label(label), do: Thereish.Chronicle.FairnessTap.label_human(label)

  defp page_track(page), do: Chronicle.page_track(page)
  defp page_vamp(page), do: Chronicle.page_vamp(page)

  attr :role, :string, required: true
  attr :label, :string, required: true
  attr :name, :string, required: true
  attr :name_role, :string, required: true
  attr :src, :string, required: true
  attr :loop, :boolean, default: false

  defp chronicle_audio(assigns) do
    ~H"""
    <div
      data-role={@role}
      class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 rounded-lg bg-base-200/50 p-3"
    >
      <div class="flex items-center gap-2">
        <span class="text-xs font-semibold uppercase tracking-wider opacity-60">{@label}</span>
        <span data-role={@name_role} class="text-sm font-medium">{@name}</span>
      </div>
      <audio
        data-role={"#{@role}-player"}
        controls
        src={@src}
        preload="none"
        loop={@loop}
        class="h-8 max-w-full sm:max-w-xs"
      >
        Your browser does not support the audio element.
      </audio>
    </div>
    """
  end

  attr :url, :string, required: true
  attr :alt, :string, required: true
  attr :seat_id, :any, default: nil
  attr :class, :string, default: "h-8 w-8 rounded-md object-cover"

  defp enlargeable_mask(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="enlarge_mask"
      phx-value-url={@url}
      phx-value-alt={@alt}
      data-role="enlarge-mask"
      data-seat={@seat_id}
      class="rounded-md focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
      aria-label={"Enlarge #{@alt}"}
    >
      <img src={@url} alt={@alt} class={@class} data-role="page-mask" />
    </button>
    """
  end
end
