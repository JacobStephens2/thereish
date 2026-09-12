defmodule ThereishWeb.RoomLive do
  @moduledoc """
  A phone in the Room: type a name, or already be someone.

  Mount asks the Room whether this browser's device token already holds a Seat.
  If it does — a locked phone waking up, a tab reopened days later — there is no
  name form and no ceremony; the player is simply back where they were. That is
  the whole of the rejoin story, and it is the same code path as a first visit.

  Every refresh of this view is a full snapshot from the Room, never a patch
  applied to what the view happened to be holding, so a phone that missed
  messages while asleep cannot end up subtly out of date.

  The one thing this view holds that the Room does not is the Bridge being
  typed. An uncommitted Bridge is nobody's business, including the Room's, so it
  lives in the text field until the player commits it — which is also why the
  field carries no value the server sets: a re-render caused by the other phone
  must never rewrite what this one is in the middle of typing.
  """
  use ThereishWeb, :live_view

  import ThereishWeb.RoomComponents

  alias Thereish.Rooms
  alias Thereish.Rooms.Code
  alias Thereish.Rooms.Seat
  alias ThereishWeb.DeviceToken

  @impl true
  def mount(params, session, socket) do
    slug = Rooms.open!(params["slug"])
    device_token = DeviceToken.from_session(session)

    if connected?(socket) do
      Rooms.subscribe(slug)
      ThereishWeb.Presence.track_phone(socket, slug)
    end

    {:ok,
     socket
     |> assign(:slug, slug)
     |> assign(:join_url, url(~p"/r/#{slug}"))
     |> assign(:device_token, device_token)
     |> assign(:name, "")
     |> assign(:error, nil)
     |> assign(:bridge_error, nil)
     |> assign(:page_error, nil)
     |> assign(:give_input, "")
     |> assign(:give_error, nil)
     |> assign(:seat, seat_for_device(slug, device_token))
     |> assign(:room, nil)
     |> resync()}
  end

  @impl true
  def handle_event("join", params, socket) do
    name = params["name"] || ""

    case Rooms.join(socket.assigns.slug, name, socket.assigns.device_token) do
      {:ok, seat} ->
        {:noreply, socket |> assign(seat: seat, error: nil) |> resync()}

      {:error, reason} ->
        {:noreply, assign(socket, name: name, error: message(reason))}
    end
  end

  def handle_event("validate_bridge", %{"bridge" => bridge}, socket) do
    barred =
      (socket.assigns.room &&
         (Map.get(socket.assigns.room, :barred_words) ||
            Map.get(socket.assigns.room, :bookends))) || []

    trimmed = String.trim(bridge)

    error =
      if trimmed == "" do
        nil
      else
        case Thereish.Steward.Legality.check_bridge(bridge, barred) do
          :ok -> nil
          {:illegal, why} -> why
        end
      end

    {:noreply, assign(socket, :bridge_error, error)}
  end

  def handle_event("commit_bridge", %{"bridge" => bridge}, socket) do
    case Rooms.commit_bridge(socket.assigns.slug, socket.assigns.seat.id, bridge) do
      :ok ->
        {:noreply,
         socket
         |> assign(:bridge_error, nil)
         |> ThereishWeb.Foley.push_own_commit()
         |> resync()}

      {:error, reason} ->
        {:noreply, assign(socket, :bridge_error, message(reason))}
    end
  end

  # Both phones can reach the same button, and on a couch both of them will.
  # Whichever tap lands second is answered by the Room with the state the first
  # one left, so there is nothing to say about it beyond showing what is there.
  def handle_event("next_attempt", _params, socket) do
    Rooms.next_attempt(socket.assigns.slug, socket.assigns.seat.id)

    {:noreply, resync(socket)}
  end

  def handle_event("next_page", _params, socket) do
    case Rooms.next_page(socket.assigns.slug, socket.assigns.seat.id) do
      :ok ->
        {:noreply, socket |> assign(:page_error, nil) |> resync()}

      {:error, reason} ->
        {:noreply, assign(socket, :page_error, message(reason))}
    end
  end

  def handle_event("propose_overrule", _params, socket) do
    Rooms.propose_overrule(socket.assigns.slug, socket.assigns.seat.id)

    {:noreply, resync(socket)}
  end

  def handle_event("agree_overrule", _params, socket) do
    Rooms.agree_overrule(socket.assigns.slug, socket.assigns.seat.id)

    {:noreply, resync(socket)}
  end

  def handle_event("decline_overrule", _params, socket) do
    Rooms.decline_overrule(socket.assigns.slug, socket.assigns.seat.id)

    {:noreply, resync(socket)}
  end

  def handle_event("fairness_tap", %{"label" => label}, socket) do
    if socket.assigns.seat do
      Rooms.record_fairness_tap(socket.assigns.slug, socket.assigns.seat.id, label)
    end

    {:noreply, resync(socket)}
  end

  def handle_event("bookends_tap", %{"label" => label}, socket) do
    if socket.assigns.seat do
      Rooms.tap_bookends(socket.assigns.slug, socket.assigns.seat.id, label)
    end

    {:noreply, resync(socket)}
  end

  def handle_event("submit_give", %{"give" => give}, socket) do
    trimmed = String.trim(give || "")

    if trimmed == "" do
      {:noreply, assign(socket, :give_error, "Type a setting first.")}
    else
      case Rooms.give(socket.assigns.slug, socket.assigns.seat.id, trimmed) do
        :ok ->
          {:noreply, socket |> assign(give_input: "", give_error: nil) |> resync()}

        {:error, reason} ->
          {:noreply, assign(socket, :give_error, message(reason))}
      end
    end
  end

  def handle_event("start_page", _params, socket) do
    case Rooms.start_page(socket.assigns.slug, socket.assigns.seat.id) do
      :ok ->
        {:noreply, socket |> assign(:give_error, nil) |> resync()}

      {:error, reason} ->
        {:noreply, assign(socket, :give_error, message(reason))}
    end
  end

  def handle_event("retry_author", _params, socket) do
    Rooms.retry_author(socket.assigns.slug, socket.assigns.seat.id)
    {:noreply, resync(socket)}
  end

  def handle_event("reset_gives", _params, socket) do
    Rooms.reset_gives(socket.assigns.slug, socket.assigns.seat.id)
    {:noreply, resync(socket)}
  end

  def handle_event("claim_speaker", _params, socket) do
    Rooms.claim_speaker(socket.assigns.slug, socket.assigns.device_token)
    {:noreply, resync(socket)}
  end

  def handle_event("toggle_quips", _params, socket) do
    current = Map.get(socket.assigns.room, :quips, true)
    Rooms.set_quips(socket.assigns.slug, !current)
    {:noreply, resync(socket)}
  end

  def handle_event("toggle_full_table", _params, socket) do
    current = Map.get(socket.assigns.room, :full_table, true)
    Rooms.set_full_table(socket.assigns.slug, !current)
    {:noreply, resync(socket)}
  end

  def handle_event("set_music", %{"music" => music}, socket) do
    Rooms.set_music(socket.assigns.slug, music)
    {:noreply, resync(socket)}
  end

  def handle_event("next_music", _params, socket) do
    Rooms.next(socket.assigns.slug, socket.assigns.device_token)
    {:noreply, resync(socket)}
  end

  def handle_event("never_music", _params, socket) do
    Rooms.never(socket.assigns.slug, socket.assigns.device_token)
    {:noreply, resync(socket)}
  end

  def handle_event("skip_prologue", _params, socket) do
    Rooms.skip_prologue(socket.assigns.slug)
    {:noreply, resync(socket)}
  end

  # The phone woke up. Ask for the whole view rather than trusting what is on
  # screen, because whatever happened while the screen was off is unknowable
  # from here.
  def handle_event("resync", _params, socket), do: {:noreply, resync(socket)}

  @impl true
  def handle_info(:room_changed, socket), do: {:noreply, resync(socket)}

  # A recap landing is news for the book and for nothing on this screen. It
  # arrives here because the Scribe broadcasts on the Room's topic, and it is
  # ignored here on purpose rather than by a catch-all: a message this screen
  # does not know about should still be a crash.
  def handle_info(:chronicle_changed, socket), do: {:noreply, socket}

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply,
     socket
     |> assign(:stage_present?, ThereishWeb.Presence.stage_present?(socket.assigns.slug))}
  end

  def handle_info({:voice_ready, attempt}, socket) do
    {:noreply, ThereishWeb.Foley.push_voice(socket, attempt)}
  end

  defp seat_for_device(slug, device_token) do
    case Rooms.rejoin(slug, device_token) do
      {:ok, seat} -> seat
      :error -> nil
    end
  end

  defp resync(socket) do
    seat_id = socket.assigns.seat && socket.assigns.seat.id
    old_room = socket.assigns[:room]
    new_room = Rooms.snapshot(socket.assigns.slug, seat_id, socket.assigns.device_token)
    seat = (new_room && new_room.you) || socket.assigns.seat

    socket
    |> assign(:room, new_room)
    |> assign(:seat, seat)
    |> assign(:stage_present?, ThereishWeb.Presence.stage_present?(socket.assigns.slug))
    |> ThereishWeb.Foley.push_foley_events(old_room, new_room)
  end

  defp message(:give_required), do: "Type a setting first."
  defp message(:name_required), do: "Type a name first."
  defp message(:name_too_long), do: "That name is longer than #{Seat.name_max()} characters."
  defp message(:room_full), do: "Every seat is taken. Ask whoever is in there to make room."
  defp message(:could_not_join), do: "Something went wrong taking a seat. Try again."
  defp message(:bridge_required), do: "Write a word first."
  defp message(:already_committed), do: "That one is committed. No taking it back."
  defp message(:not_bridging), do: "Too late for this one."
  defp message(:no_such_seat), do: "You are not in this Room any more. Reload."
  defp message({:illegal_bridge, reason}), do: reason
  defp message(:not_enough_gives), do: "Need at least two settings to start."
  defp message(:not_playing_page), do: "You're watching this Page."
  defp message(:pool_exhausted), do: "That's every Page for tonight."
  defp message(_), do: "Something went wrong. Try again."

  defp can_overrule?(nil, _seat), do: false
  defp can_overrule?(%{reveal: nil}, _seat), do: false
  defp can_overrule?(%{overrule: %{pending?: true}}, _seat), do: false

  defp can_overrule?(%{reveal: %{overruled?: true}}, _seat), do: false
  defp can_overrule?(_room, _seat), do: true

  defp playing_phase?(nil), do: false
  defp playing_phase?(room), do: room.phase not in [:waiting, :giving]

  defp chronicle_path(slug), do: ~p"/r/#{slug}/chronicle"

  defp find_seat_colour(room, seat_id) do
    seat = Enum.find(room[:seats] || [], &(&1.id == seat_id))
    (seat && seat[:colour]) || "currentColor"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <main
      id="room"
      phx-hook=".ResyncOnWake"
      class="mx-auto flex min-h-screen max-w-md flex-col justify-center gap-8 px-6 py-12"
    >
      <%= if not playing_phase?(@room) do %>
        <.speaker_bar_and_code
          room={@room}
          code={@slug}
          join_url={@join_url}
          stage_present?={@stage_present?}
        />

        <section
          :if={
            @room && not @stage_present? && @room.phase == :waiting && not @room.prologue_skipped &&
              not @room[:has_chronicle?]
          }
          data-role="prologue-card"
          class="flex flex-col gap-3 rounded-lg border border-base-300 p-4 text-center"
        >
          <p class="text-xs uppercase tracking-widest font-semibold text-primary">The Prologue</p>
          <p data-role="prologue-words" class="text-sm leading-relaxed opacity-90">
            {@room[:prologue_script]}
          </p>
          <div>
            <button
              type="button"
              phx-click="skip_prologue"
              data-role="prologue-skip"
              class="btn btn-ghost btn-xs text-xs opacity-70 hover:opacity-100"
            >
              Skip
            </button>
          </div>
        </section>

        <div :if={@room && @stage_present? && @room[:prologue]} class="flex justify-center">
          <button
            type="button"
            phx-click="skip_prologue"
            data-role="prologue-skip"
            class="btn btn-ghost btn-xs text-xs opacity-70 hover:opacity-100"
          >
            Skip Prologue
          </button>
        </div>
      <% end %>

      <form :if={@seat == nil} phx-submit="join" class="flex flex-col gap-2">
        <.input name="name" value={@name} label="Your name" autocomplete="off" autofocus />
        <p :if={@error} data-role="error" class="text-sm text-error">{@error}</p>
        <.button variant="primary">Join</.button>
      </form>

      <div
        :if={@seat && @room[:late?]}
        data-role="late-seat"
        class="flex flex-col items-center gap-2 rounded-xl border border-primary/30 bg-primary/5 p-4 text-center"
      >
        <p class="text-xs uppercase tracking-widest font-semibold text-primary">Watching this Page</p>
        <p class="text-sm">
          You joined mid-Page. Watching this Page — you'll play on the next one!
        </p>
      </div>

      <form
        :if={@seat && !@room[:late?] && @room.phase == :giving && @room.your_give == nil}
        id="setting-form"
        data-role="setting-form"
        phx-submit="submit_give"
        class="flex flex-col gap-2"
      >
        <.input
          name="give"
          value={if(@give_input != "", do: @give_input, else: @room.your_last_give)}
          label="Your setting"
          placeholder="e.g. the world St. Thérèse grew up in"
          autocomplete="off"
          autofocus
        />
        <p :if={@give_error} data-role="give-error" class="text-sm text-error">
          {@give_error}
        </p>
        <.button variant="primary">Set</.button>
      </form>

      <div
        :if={@seat && !@room[:late?] && @room.phase == :giving && @room.your_give != nil}
        data-role="your-give"
        class="flex flex-col items-center gap-1 text-center"
      >
        <p class="text-xs uppercase tracking-widest font-semibold text-primary">Your setting</p>
        <div
          :if={@room[:your_mask] && @room.your_mask not in [nil, :dot]}
          data-role="your-mask"
          class="my-2"
        >
          <img
            src={@room.your_mask[:url] || @room.your_mask["url"] || @room.your_mask}
            alt="Your Mask"
            class="size-24 rounded-xl shadow-md object-cover border border-base-300"
          />
        </div>
        <div
          :if={@room[:your_mask] == :dot}
          data-role="your-mask-dot"
          class="my-2 size-5 rounded-full"
          style={"background-color: #{find_seat_colour(@room, @seat.id)}"}
        >
        </div>
        <p class="text-xl font-semibold">{@room.your_give}</p>
        <p class="text-sm opacity-60">
          <%= if @room.gives_in >= length(@room.seats) do %>
            Everyone is in ({@room.gives_in} of {length(@room.seats)} in)
          <% else %>
            Waiting for {length(@room.seats) - @room.gives_in} more ({@room.gives_in} of {length(
              @room.seats
            )} in)
          <% end %>
        </p>
      </div>

      <div
        :if={
          @seat && !@room[:late?] && @room.phase == :giving && @room.your_give != nil &&
            @room.gives_in >= 2
        }
        class="flex justify-center"
      >
        <.button phx-click="start_page" data-role="start-page" variant="primary">
          Start Page
        </.button>
      </div>

      <div
        :if={@seat && @room.phase == :writing && is_nil(@room[:author_failure])}
        data-role="writing-phase"
        class="flex flex-col items-center justify-center gap-3 text-center"
      >
        <.author_writing room={@room} mode={:phone} />
      </div>

      <div
        :if={@seat && @room[:author_failure]}
        data-role="author-failure"
        class="flex flex-col items-center gap-3 rounded-xl border border-warning/40 bg-warning/10 p-5 text-center"
      >
        <p class="text-xs uppercase tracking-widest font-semibold text-warning">Setting Notice</p>
        <p class="text-sm font-medium">
          The Author couldn't write from these settings: {@room.author_failure}
        </p>
        <div class="flex gap-2 mt-2">
          <.button phx-click="retry_author" data-role="retry-author" variant="primary">Try again</.button>
          <.button phx-click="reset_gives" data-role="reset-gives">New settings</.button>
        </div>
      </div>
      <.attempt :if={@seat} room={@room} />

      <.bookends :if={@seat} room={@room} />

      <form
        :if={@seat && !@room[:late?] && @room.phase == :bridging && @room.your_bridge == nil}
        id="bridge-form"
        data-role="bridge-form"
        phx-change="validate_bridge"
        phx-submit="commit_bridge"
        class="flex flex-col gap-2"
      >
        <.input
          name="bridge"
          value={nil}
          label="Your bridge"
          autocomplete="off"
          autofocus
        />
        <p :if={@bridge_error} data-role="bridge-error" class="text-sm text-error">
          {@bridge_error}
        </p>
        <.button variant="primary">Commit</.button>
      </form>

      <div :if={!@room[:late?] && @room.your_bridge && mid_page?(@room)} class="flex flex-col gap-1">
        <p data-role="your-bridge" class="text-lg">
          Your bridge: <span class="font-semibold">{@room.your_bridge}</span>
        </p>
        <p :if={@room.phase == :bridging} class="text-sm opacity-60">Waiting for the others.</p>
      </div>

      <.assaying room={@room} />

      <.reveal
        room={@room}
        seat={@seat}
        mode={if @stage_present? and not (@room && @room.speaker?), do: :quiet, else: :phone}
      />

      <.overrule_banner room={@room} seat={@seat} />

      <div
        :if={@seat && !@room[:late?] && can_overrule?(@room, @seat)}
        class="flex justify-center"
      >
        <.button phx-click="propose_overrule" data-role="propose-overrule">
          Overrule the Assayer
        </.button>
      </div>

      <div
        :if={@seat && !@room[:late?] && @room.phase == :reveal}
        class="flex flex-col items-center gap-2 border-t border-base-300 pt-6"
      >
        <.carry_forward room={@room} />
        <.button phx-click="next_attempt" data-role="again" variant="primary">
          Again — {join_and(@room.next_bookends)}
        </.button>
      </div>

      <.ending room={@room} seat={@seat} mode={:phone} />

      <div :if={@seat && @room.phase == :closed} class="flex flex-col items-center gap-2">
        <p :if={@page_error} data-role="page-error" class="text-sm text-error">{@page_error}</p>
        <.button phx-click="next_page" data-role="one-more" variant="primary">One more?</.button>
      </div>

      <%= if playing_phase?(@room) do %>
        <.speaker_bar_and_code
          room={@room}
          code={@slug}
          join_url={@join_url}
          stage_present?={@stage_present?}
        />
      <% end %>

      <section class="flex flex-col gap-2">
        <h2 class="text-sm uppercase tracking-wide opacity-60">In the Room</h2>
        <.roster room={@room} />
        <div class="mt-1">
          <.link
            navigate={~p"/new"}
            data-role="start-another-room"
            class="text-sm font-medium underline opacity-70 hover:opacity-100"
          >
            Start another Room
          </.link>
        </div>
      </section>

      <footer class="flex flex-col gap-3 border-t border-base-300 pt-6">
        <p :if={@seat} data-role="you" class="text-center text-sm opacity-80">
          You are <span class="font-semibold">{@seat.name}</span>.
        </p>
        <div class="flex items-center justify-between">
          <h1 class="text-lg font-semibold">Thereish</h1>
          <.link
            navigate={chronicle_path(@slug)}
            class="text-sm font-medium underline opacity-70 hover:opacity-100"
          >
            The Chronicle
          </.link>
        </div>
        <Layouts.made_by />
      </footer>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ResyncOnWake">
        export default {
          mounted() {
            this.onVisible = () => {
              if (document.visibilityState === "visible") this.pushEvent("resync", {})
            }
            document.addEventListener("visibilitychange", this.onVisible)
          },
          destroyed() {
            document.removeEventListener("visibilitychange", this.onVisible)
          }
        }
      </script>

      <.foley_hook speaker={@room && @room.speaker?} />
    </main>
    """
  end

  defp speaker_bar_and_code(assigns) do
    assigns = assign_new(assigns, :stage_present?, fn -> false end)

    ~H"""
    <section
      :if={@room}
      data-role="speaker-bar"
      class="flex flex-col gap-2 rounded-lg border border-base-300 px-4 py-2"
    >
      <div data-role="bar-controls" class="flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <button
            type="button"
            phx-click="claim_speaker"
            data-role="speaker-toggle"
            data-speaker={
              cond do
                @room.speaker? -> "self"
                @room.speaker_claimed? -> "other"
                true -> "none"
              end
            }
            class="flex items-center gap-2 text-sm font-medium hover:opacity-80 transition-opacity"
          >
            <.speaker_icon state={
              cond do
                @room.speaker? -> :self
                @room.speaker_claimed? -> :other
                true -> :none
              end
            } />
            <span :if={@room.speaker?} class="text-primary font-semibold">This phone is speaker</span>
            <span :if={@room.speaker_claimed? and not @room.speaker?} class="opacity-60">Speaker elsewhere</span>
            <span :if={not @room.speaker_claimed?} class="opacity-60">Tap to claim speaker</span>
          </button>

          <.local_sound_switch stage_present?={@stage_present?} />
        </div>

        <.foley_switches room={@room} />
      </div>

      <.now_playing :if={@room.speaker?} room={@room} />
    </section>

    <section
      data-role="room-code"
      class="flex flex-col items-center gap-1 rounded-lg border border-base-300 px-4 py-6"
    >
      <p class="text-sm uppercase tracking-wide opacity-60">Code</p>
      <p data-role="code" class="font-mono text-5xl font-bold tracking-[0.3em]">
        {Code.shout(@code)}
      </p>
      <p
        :if={@room && @room.quip}
        data-role="code-quip"
        class="text-center text-sm italic opacity-70"
      >
        {@room.quip}
      </p>
      <p class="mt-2 text-center text-sm opacity-70">
        <.join_at url={@join_url} />
      </p>
      <div class="mt-4">
        <.button navigate={~p"/r/#{@code}/stage"} data-role="make-stage" class="btn-sm text-xs">
          Make this device the Stage
        </.button>
      </div>
    </section>
    """
  end
end
