defmodule ThereishWeb.ChronicleLive do
  @moduledoc """
  The Chronicle as a book read on a phone (ticket 08, ticket 11).

  Reads the Chronicle in reverse chronological order: every Page, every attempt,
  both Bridges, the grade, the reasoning, and any overrule. Original participants
  and the authenticated admin can record Too harsh / Fair / Too kind opinions
  without rewriting recorded play (ADR-0019). Historical corrections remain
  readable. Every view is computed from the event log.
  """
  use ThereishWeb, :live_view

  import ThereishWeb.RoomComponents

  alias Thereish.Admin
  alias Thereish.Chronicle
  alias Thereish.Chronicle.Opinion
  alias Thereish.Mask
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
     |> assign(:current_admin, admin_from_session(session))
     |> assign(:enlarged_mask, nil)
     |> load_pages()}
  end

  @impl true
  def handle_event(
        "record_opinion",
        %{"page-id" => page_id, "attempt" => attempt, "label" => label},
        socket
      ) do
    {:noreply, record_chronicle_opinion(socket, page_id, attempt, label, participant: true)}
  end

  def handle_event(
        "admin_review",
        %{"page-id" => page_id, "attempt" => attempt, "label" => label},
        socket
      ) do
    {:noreply, record_chronicle_opinion(socket, page_id, attempt, label, admin: true)}
  end

  def handle_event(event, _params, socket)
      when event in ["open_correction", "cancel_correction", "record_correction"] do
    {:noreply, socket}
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

  defp record_chronicle_opinion(socket, page_id, attempt, label, opts) do
    reviewer =
      cond do
        opts[:admin] && socket.assigns.current_admin ->
          {:admin, socket.assigns.current_admin.id}

        opts[:participant] && socket.assigns.seat ->
          {:participant, socket.assigns.seat.id}

        true ->
          nil
      end

    if reviewer do
      attempt_number =
        case Integer.parse(to_string(attempt)) do
          {number, _} -> number
          :error -> attempt
        end

      case Chronicle.record_opinion(socket.assigns.room.id, %{
             page_id: page_id,
             attempt_number: attempt_number,
             label: label,
             as: reviewer
           }) do
        {:ok, _} ->
          Phoenix.PubSub.broadcast(Thereish.PubSub, "room:#{socket.assigns.slug}", :room_changed)
          load_pages(socket)

        {:error, _} ->
          socket
      end
    else
      socket
    end
  end

  defp seat_for_device(slug, device_token) do
    if device_token do
      case Rooms.rejoin(slug, device_token) do
        {:ok, seat} -> seat
        :error -> nil
      end
    end
  end

  defp admin_from_session(%{"admin_token" => token}) when is_binary(token) do
    Admin.get_identity_by_session_token(token)
  end

  defp admin_from_session(_session), do: nil

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
                  :if={page.full_table == true}
                  data-role="page-rule"
                  class="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary"
                >
                  Full table
                </span>
                <span
                  :if={page.full_table == false}
                  data-role="page-rule"
                  class="rounded-full bg-base-300 px-2.5 py-0.5 text-xs font-semibold opacity-80"
                >
                  Two Bookends
                </span>
                <span
                  :for={g <- page.gives}
                  data-role="give-tag"
                  class="inline-flex items-center gap-1.5 rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary"
                >
                  <.enlargeable_mask
                    :if={Mask.url(g.mask)}
                    url={Mask.url(g.mask)}
                    alt={"Mask for " <> g.seat_name}
                    seat_id={g.seat_id}
                    class="h-4 w-4 rounded-full object-cover"
                  />
                  <span>Give ({g.seat_name}): {g.text}</span>
                </span>
                <span
                  :if={page.gives == [] and page.give}
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
            :if={is_map(page.masks) and Enum.any?(page.masks, fn {_, m} -> Mask.url(m) end)}
            data-role="page-masks"
            class="flex items-center gap-3 rounded-lg bg-base-200/50 p-3"
          >
            <span class="text-xs font-semibold uppercase tracking-wider opacity-60">Masks</span>
            <div class="flex flex-wrap items-center gap-2">
              <.enlargeable_mask
                :for={{seat_id, mask} <- page.masks}
                :if={Mask.url(mask)}
                url={Mask.url(mask)}
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
                room={%{bookend_chips: attempt.bookend_chips}}
                mode={:phone}
              />

              <p
                :for={chip <- attempt.bookend_chips}
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
                    :if={b.corrected? && b.original_bridge}
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
                :if={attempt.carried && attempt.carried != []}
                data-role="carried-words"
                class="text-xs opacity-70"
              >
                Carried: <span class="font-medium">{join_and(attempt.carried)}</span>
              </p>

              <!-- Fairness taps on this attempt -->
              <div
                :if={attempt.fairness_taps != []}
                data-role="fairness-taps"
                class="mt-1 flex flex-wrap items-center gap-1.5 text-xs"
              >
                <span class="text-[10px] font-semibold uppercase tracking-wider opacity-60">
                  Fairness:
                </span>
                <span
                  :for={t <- attempt.fairness_taps}
                  data-role={if t.source == "admin", do: "admin-review", else: "fairness-tap-entry"}
                  data-source={t.source}
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
                  {t.reviewer_name}: {human_label(t.label)}
                </span>
              </div>

              <div
                :if={@seat && Opinion.may_give?(attempt, {:participant, @seat.id})}
                data-role="opinion-controls"
                class="mt-2 flex flex-col gap-1"
              >
                <span class="text-[10px] font-semibold uppercase tracking-wider opacity-60">
                  Was this grade fair?
                </span>
                <.opinion_row
                  event="record_opinion"
                  page_id={page.id}
                  attempt={attempt.number}
                  current={Opinion.of(attempt.fairness_taps, {:participant, @seat.id})}
                />
              </div>

              <div
                :if={@current_admin && Opinion.may_give?(attempt, {:admin, @current_admin.id})}
                data-role="admin-review-controls"
                class="mt-2 flex flex-col gap-1"
              >
                <span class="text-[10px] font-semibold uppercase tracking-wider opacity-60">
                  Admin review
                </span>
                <.opinion_row
                  event="admin_review"
                  page_id={page.id}
                  attempt={attempt.number}
                  current={Opinion.of(attempt.fairness_taps, {:admin, @current_admin.id})}
                />
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

  defp human_label(label), do: Opinion.human(label)

  attr :event, :string, required: true
  attr :page_id, :string, required: true
  attr :attempt, :integer, required: true
  attr :current, :string, default: nil

  defp opinion_row(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center gap-1.5">
      <.opinion_button
        :for={label <- Opinion.labels()}
        event={@event}
        page_id={@page_id}
        attempt={@attempt}
        label={label}
        current={@current}
      >
        {String.capitalize(Opinion.human(label))}
      </.opinion_button>
    </div>
    """
  end

  attr :event, :string, required: true
  attr :page_id, :string, required: true
  attr :attempt, :integer, required: true
  attr :label, :string, required: true
  attr :current, :string, default: nil
  slot :inner_block, required: true

  defp opinion_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-page-id={@page_id}
      phx-value-attempt={@attempt}
      phx-value-label={@label}
      data-role={"tap-#{String.replace(@label, "_", "-")}"}
      data-tap={@label}
      class={[
        "btn btn-xs font-medium",
        if(@current == @label,
          do: "btn-primary font-bold",
          else: "btn-ghost border border-base-300 opacity-80 hover:opacity-100"
        )
      ]}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

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
