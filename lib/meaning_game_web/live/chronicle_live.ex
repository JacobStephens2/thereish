defmodule MeaningGameWeb.ChronicleLive do
  @moduledoc """
  The Chronicle as a book read on a phone (ticket 08).

  Reads the Chronicle in reverse chronological order: every Page, every attempt,
  both Bridges, the grade, the reasoning, and any overrule. Players can correct
  an entry, and the correction is recorded as another append-only event rather
  than mutating past Pages (design law 5, ADR-0003).

  Every view is computed from the event log.
  """
  use MeaningGameWeb, :live_view

  alias MeaningGame.Chronicle
  alias MeaningGame.Repo
  alias MeaningGame.Rooms
  alias MeaningGame.Rooms.Room
  alias MeaningGameWeb.DeviceToken

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
        Phoenix.PubSub.broadcast(MeaningGame.PubSub, "room:#{socket.assigns.slug}", :room_changed)

        {:noreply,
         socket
         |> assign(correcting_page_id: nil, correction_params: default_correction_params())
         |> load_pages()}

      {:error, _changeset} ->
        {:noreply, assign(socket, :correction_params, params)}
    end
  end

  def handle_event("unblind_experiment", _params, socket) do
    room_id = socket.assigns.room.id
    seat_id = socket.assigns.seat && socket.assigns.seat.id

    {:ok, _} =
      Chronicle.record_experiment_unblinding(room_id, %{
        experiment_id: "bait_against_plain",
        seat_id: seat_id,
        unblinded_at: DateTime.utc_now(),
        notes: "Deliberate unblinding from Chronicle"
      })

    Phoenix.PubSub.broadcast(MeaningGame.PubSub, "room:#{socket.assigns.slug}", :room_changed)

    {:noreply, load_pages(socket)}
  end

  @impl true
  def handle_info(:room_changed, socket), do: {:noreply, load_pages(socket)}
  def handle_info(:chronicle_changed, socket), do: {:noreply, load_pages(socket)}

  defp load_pages(socket) do
    room_id = socket.assigns.room.id
    pages = Chronicle.book(room_id)
    unblinded = Chronicle.experiment_unblinded?(room_id, "bait_against_plain")
    readout = Chronicle.experiment_readout(room_id, "bait_against_plain")
    spend = Chronicle.spend(room_id)

    socket
    |> assign(:pages, pages)
    |> assign(:unblinded, unblinded)
    |> assign(:readout, readout)
    |> assign(:spend, spend)
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
          <h1 class="text-3xl font-bold tracking-tight">The Chronicle</h1>
          <.link
            navigate={room_path(@slug)}
            class="text-sm font-medium underline opacity-70 hover:opacity-100"
          >
            ← Back to Room
          </.link>
        </div>
        <div class="flex items-center justify-between text-sm opacity-60">
          <span>Room: {@slug}</span>
          <div class="flex items-center gap-3">
            <a href={export_path(@slug)} class="underline hover:opacity-100" download>
              Export Markdown (.md)
            </a>
            <span>·</span>
            <a href={export_calibration_path(@slug)} class="underline hover:opacity-100" download>
              Export Calibration (.json)
            </a>
          </div>
        </div>
      </header>

      <!-- Experiment Harness (Ticket 13) -->
      <section
        data-role="experiment-card"
        class="flex flex-col gap-3 rounded-xl border border-base-300 bg-base-100 p-5 shadow-sm"
      >
        <div class="flex items-start justify-between gap-2 border-b border-base-200 pb-3">
          <div>
            <div class="flex items-center gap-2">
              <span class="text-xs font-bold uppercase tracking-wider opacity-60">Experiment</span>
              <span
                :if={!@unblinded}
                data-role="blinded-banner"
                class="rounded-full bg-base-200 px-2.5 py-0.5 text-xs font-semibold opacity-70"
              >
                Blinded during play
              </span>
              <span
                :if={@unblinded}
                data-role="unblinded-banner"
                class="rounded-full bg-primary/20 px-2.5 py-0.5 text-xs font-semibold text-primary"
              >
                Deliberately Unblinded
              </span>
            </div>
            <h2 class="text-xl font-bold tracking-tight mt-1">Bait against plain</h2>
            <p class="text-xs opacity-70 mt-0.5">
              Testing ADR-0004's misdirection decision. Declared sample size: 20 Pages.
            </p>
          </div>
          <div>
            <button
              :if={!@unblinded}
              phx-click="unblind_experiment"
              data-role="unblind-button"
              class="rounded-lg bg-neutral px-3 py-1.5 text-xs font-semibold text-neutral-content hover:opacity-90 cursor-pointer"
            >
              Unblind Experiment
            </button>
          </div>
        </div>

        <div class="text-xs opacity-75">
          <p>
            <span class="font-semibold">Declared outcomes:</span>
            Meld rate, attempts to meld, fairness preferences, overrules, and bait trap convergence.
          </p>
        </div>

        <!-- Qualitative Readout when unblinded -->
        <div
          :if={@unblinded && @readout}
          data-role="experiment-readout"
          class="flex flex-col gap-3 mt-1 pt-3 border-t border-base-200"
        >
          <h3 class="text-sm font-bold uppercase tracking-wider opacity-70">Qualitative Readout</h3>

          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <.arm_readout_card
              data_role="readout-arm-bait"
              title="Bait-scored Pages"
              title_class="text-secondary"
              summary={@readout.bait}
              extra_label="Traps sprung"
              extra_value={@readout.bait.trap_sprung_count}
            />

            <.arm_readout_card
              data_role="readout-arm-plain"
              title="Plain Pages"
              title_class="opacity-80"
              summary={@readout.plain}
              extra_label="Overrules"
              extra_value={@readout.plain.overrules_count}
            />
          </div>

          <div
            data-role="readout-narrative"
            class="rounded-lg bg-base-200/30 p-3 text-xs italic opacity-90 border border-base-300/50"
          >
            "{@readout.summary_narrative}"
          </div>
        </div>
      </section>

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
                  :for={g <- page[:gives] || []}
                  data-role="give-tag"
                  class="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary"
                >
                  Give ({g.seat_name}): {g.text}
                </span>
                <span
                  :if={(page[:gives] == nil or page[:gives] == []) and page[:give]}
                  data-role="give-tag"
                  class="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary"
                >
                  Give: {page.give}
                </span>
                <span
                  :if={page[:experiment_unblinded] && page[:arm]}
                  data-role="arm-tag"
                  class="rounded-full bg-secondary/15 px-2.5 py-0.5 text-xs font-semibold text-secondary"
                >
                  Arm: {String.capitalize(page.arm)}
                </span>
                <span
                  :if={page[:experiment_unblinded] && page[:trap_converged]}
                  data-role="trap-tag"
                  class="rounded-full bg-warning/20 px-2.5 py-0.5 text-xs font-semibold text-warning"
                >
                  Bait trap sprung
                </span>
                <span
                  :if={page[:experiment_unblinded] && page[:deep_converged]}
                  data-role="deep-tag"
                  class="rounded-full bg-info/20 px-2.5 py-0.5 text-xs font-semibold text-info"
                >
                  Deep meld
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
                <span :if={attempt.bookends != page.bookends}>
                  Bookends: {Enum.join(attempt.bookends, " · ")}
                </span>
              </div>

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

      <footer
        data-role="chronicle-spend"
        class="border-t border-base-300 pt-6 pb-12 text-sm text-base-content/80"
      >
        <p data-role="spend-line" class="font-mono text-xs opacity-75">
          {Chronicle.spend_line(@spend)}
        </p>
      </footer>
    </main>
    """
  end

  defp room_path(slug), do: ~p"/r/#{slug}"

  defp export_path(slug), do: ~p"/r/#{slug}/chronicle.md"

  defp export_calibration_path(slug), do: ~p"/r/#{slug}/calibration.json"

  defp human_label(label), do: MeaningGame.Chronicle.FairnessTap.label_human(label)

  attr :data_role, :string, required: true
  attr :title, :string, required: true
  attr :title_class, :string, default: "opacity-80"
  attr :summary, :map, required: true
  attr :extra_label, :string, default: nil
  attr :extra_value, :any, default: nil

  defp arm_readout_card(assigns) do
    ~H"""
    <div
      data-role={@data_role}
      class="rounded-lg bg-base-200/60 p-3 flex flex-col gap-1 text-xs"
    >
      <span class={["font-bold text-sm", @title_class]}>{@title}</span>
      <div>Pages played: <span class="font-semibold">{@summary.pages_count}</span></div>
      <div>Meld rate: <span class="font-semibold">{@summary.meld_rate}</span></div>
      <div>
        Mean attempts: <span class="font-semibold">{@summary.mean_attempts_to_meld}</span>
      </div>
      <div :if={@extra_label && @extra_value != nil}>
        {@extra_label}: <span class="font-semibold">{@extra_value}</span>
      </div>
      <div class="mt-1 opacity-75">Fairness: {@summary.fairness_summary}</div>
    </div>
    """
  end
end
