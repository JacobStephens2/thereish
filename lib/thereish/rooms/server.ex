defmodule Thereish.Rooms.Server do
  @moduledoc """
  One supervised process per Room, holding that Room's row and its Play.

  Talk to it through `Thereish.Rooms`, never directly. It is the only thing
  that decides who is in the Room; the LiveViews only ask it and render what
  comes back.

  Every Seat it knows about is in Postgres, so a crash restarts it clean:
  `init/1` reloads the Room and its Seats and rebuilds the Play from them.
  That is also why reconnect is a snapshot rather than a replay — a client that
  went away asks the current state and gets it, and no message it missed
  matters.

  The Page in progress is the exception, and it is a real one: Bridges and
  verdicts live in this process and nowhere else, so a Room that crashes
  mid-Page comes back at the Bookends with both Bridges gone. The Chronicle is
  written when a Page closes, not as it is played, so a crash costs the Page
  that was in flight — never a Page that finished, and never the Seats.

  ## Rules of play are Play's

  Every rule about the Room's play, from the Game to Pacing, Pages,
  Occupancy, Voice and Room facts, and the order in which they are told
  things, lives in `Thereish.Rooms.Play`. This process reads the clock, runs
  each command through `Play.apply/3`, and performs the effects it answers,
  in order: Postgres writes, Steward asks, timers and broadcasts. It answers
  the asks that need Postgres with Play's follow-up commands, and it owns
  rescue-and-log, so a failed write never takes the Room down.
  """
  use GenServer, restart: :permanent

  require Logger

  alias Thereish.Chronicle
  alias Thereish.Experiments
  alias Thereish.Mask
  alias Thereish.Rooms.Play
  alias Thereish.Rooms.Seat
  alias Thereish.Rooms.Store
  alias Thereish.Scribe
  alias Thereish.Steward

  def start_link(opts) do
    slug = Keyword.fetch!(opts, :slug)
    GenServer.start_link(__MODULE__, opts, name: via(slug))
  end

  @doc "The registered name of the Room process with this slug."
  def via(slug), do: {:via, Registry, {Thereish.Rooms.Registry, slug}}

  @impl true
  def init(opts) do
    slug = Keyword.fetch!(opts, :slug)

    # A Room is created through `Thereish.Rooms.create/2` and nowhere else,
    # so a process asked to start for a Code no Room has is a bug upstream, not
    # a Room to bring into being.
    with %{} = room <- Store.get_room(slug) do
      play =
        Play.new(
          %{room: room, seats: Store.list_seats(room.id)},
          %{members: members(room), durations: durations(), now: now()}
        )

      {:ok, %{slug: slug, room: room, play: play}}
    else
      nil -> {:stop, {:no_such_room, slug}}
    end
  end

  @impl true
  def handle_call({:join, name, device_token}, _from, state) do
    case held_seat(state, name, device_token) do
      %Seat{} = seat -> rejoin_seat(seat, device_token, state)
      nil -> take_seat(name, device_token, state)
    end
  end

  def handle_call({:rejoin, device_token}, _from, state) do
    case Store.seat_by_device_token(state.room.id, device_token) do
      %Seat{} = seat -> {:reply, {:ok, public(seat)}, state}
      nil -> {:reply, :error, state}
    end
  end

  def handle_call({:voice_audio, attempt, kind}, _from, state) do
    {:reply, Play.clip(state.play, attempt, kind), state}
  end

  def handle_call(:in_play?, _from, state) do
    {:reply, Play.in_play?(state.play), state}
  end

  # The snapshot answers how long the Assayer has been thinking, plus the
  # Room facts for the requesting viewer's device token. Device tokens never
  # leave the Room.
  def handle_call({:snapshot, viewer}, from, state) do
    handle_call({:snapshot, viewer, nil}, from, state)
  end

  def handle_call({:snapshot, viewer, device_token}, _from, state) do
    reads = %{now: now(), has_chronicle?: has_chronicle?(state)}
    {:reply, Play.view(state.play, viewer, device_token, reads), state}
  end

  # Every other request is a command of play.
  def handle_call(command, _from, state) do
    case run(state, with_reads(command, state)) do
      {:ok, state, _guarded} -> {:reply, :ok, state}
      {:error, reason, state} -> {:reply, {:error, reason}, state}
    end
  end

  # The failure metadata reads the Steward's adapter config, so it is made
  # here and Play decides where it goes.
  @impl true
  def handle_info({:voice_spoken, attempt, kind, {:error, reason}}, state) do
    heard(state, {:voice_spoken, attempt, kind, {:error, Steward.voice_failure(reason)}})
  end

  def handle_info({:author_completed, ref, {:error, reason}}, state) do
    heard(state, {:author_completed, ref, {:error, Steward.author_failure(reason)}})
  end

  # Every background result the Room hears is a command of play.
  def handle_info(message, state), do: heard(state, message)

  defp heard(state, message) do
    {:ok, state, nil} = run(state, message)
    {:noreply, state}
  end

  # The browser's own Seat wins over the name it typed, so typing someone else's
  # name on a phone that is already seated cannot take their Seat.
  defp held_seat(state, name, device_token) do
    Store.seat_by_device_token(state.room.id, device_token) ||
      Store.seat_by_name(state.room.id, name)
  end

  # Claiming an existing Seat is allowed even when the Room is full — a full Room
  # is exactly the Room its players are trying to get back into. The new browser
  # is added to the Seat's devices rather than replacing them, so the phone that
  # was already holding this Seat keeps holding it.
  defp rejoin_seat(seat, device_token, state) do
    case Store.remember_device(seat, device_token) do
      {:ok, seat} -> {:reply, {:ok, public(seat)}, state}
      {:error, _changeset} -> {:reply, {:error, :could_not_join}, state}
    end
  end

  # The id is minted here because the rules need a Seat to rule on.
  defp take_seat(name, device_token, state) do
    case run(state, {:seat_joined, Ecto.UUID.generate(), name}, device_token: device_token) do
      {:ok, state, seat} -> {:reply, {:ok, public(seat)}, state}
      {:error, :room_full, state} -> {:reply, {:error, :room_full}, state}
      {:error, _reason, state} -> {:reply, {:error, :could_not_join}, state}
    end
  end

  # The reads a command needs before Play may rule on it: the Repertoire's
  # members a turned Page redraws from, and whether the Room has a Chronicle
  # for the Stage's first tap.
  defp with_reads({:next_page, seat_id}, state), do: {:next_page, seat_id, members(state.room)}

  defp with_reads({:room_fact, {:start_sound, device_token}}, state),
    do: {:room_fact, {:start_sound, device_token, has_chronicle?(state)}}

  defp with_reads(command, _state), do: command

  # Runs one command at one moment. A guard write is always Play's first
  # effect: it lands before the new Play is adopted, so a failed write leaves
  # the Room as it was. Answers what the guard wrote, if anything.
  defp run(state, command, opts \\ []) do
    now = now()

    with {:ok, play, effects} <- Play.apply(state.play, command, now),
         {:ok, state, guarded, effects} <- guard(state, effects, opts) do
      {:ok, perform_all(effects, %{state | play: play}, now), guarded}
    else
      {:error, reason} -> {:error, reason, state}
    end
  end

  defp guard(state, [{:insert_seat, id, name} | effects], opts) do
    case Store.insert_seat(state.room.id, id, name, opts[:device_token]) do
      {:ok, seat} -> {:ok, state, seat, effects}
      {:error, _changeset} -> {:error, :could_not_join}
    end
  end

  defp guard(state, [{:persist_room, attrs} | effects], _opts) do
    with {:ok, room} <- Store.update_room(state.room, attrs) do
      {:ok, %{state | room: room}, nil, effects}
    end
  end

  defp guard(state, effects, _opts), do: {:ok, state, nil, effects}

  defp perform_all(effects, state, now), do: Enum.reduce(effects, state, &perform(&1, &2, now))

  # An ask whose answer changes the Play is answered at once, and what the
  # answer asks for is performed before the rest of the list.
  defp follow_up(state, command, now) do
    {:ok, play, effects} = Play.apply(state.play, command, now)
    perform_all(effects, %{state | play: play}, now)
  end

  defp perform(:broadcast, state, _now) do
    broadcast(state.slug)
    state
  end

  defp perform({:broadcast, message}, state, _now) do
    broadcast(state.slug, message)
    state
  end

  # A timer is never cancelled: one that fires late carries a token Play
  # ignores.
  defp perform({:timer, name, token, ms}, state, _now) do
    Process.send_after(self(), {:pacing, name, token}, ms)
    state
  end

  defp perform({:open_page, request, arm}, state, now) do
    arm = arm || Steward.assign_arm(state.room.id)
    cached = cached_track(Enum.map(request.gives, & &1.text))
    follow_up(state, {:page_opened, request, arm, cached}, now)
  end

  defp perform({:ask_author, ref, request, arm}, state, _now) do
    digest = Chronicle.digest(state.room.id)

    Steward.answer_later(
      fn -> Steward.author(request, job: arm, digest: digest) end,
      &{:author_completed, ref, &1}
    )

    state
  end

  # An Assayer that blows up has failed to grade, which is a thing the game has
  # a rule for. It is not a thing the Room should die of.
  defp perform({:ask_assayer, request, in_play_quips}, state, _now) do
    prior_quips = Enum.take(Chronicle.recent_quips(state.room.id, 5) ++ in_play_quips, -5)
    request = Map.put(request, :prior_quips, prior_quips)
    Steward.answer_later(fn -> Steward.assay(request) end, &{:assayed, verdict_event(&1)})
    state
  end

  # A Mask that could not be drawn is worn as the Seat's dot, so a draw that
  # crashed lands as one.
  defp perform({:draw_mask, seat_id, giving_ref, give, colour}, state, _now) do
    Steward.answer_later(
      fn ->
        Logger.metadata(seat_id: seat_id)
        Mask.draw(give, colour)
      end,
      fn
        {:error, _} -> {:mask_landed, seat_id, giving_ref, :dot}
        mask -> {:mask_landed, seat_id, giving_ref, mask}
      end
    )

    state
  end

  defp perform({:speak, attempt, kind, line}, state, _now) do
    Steward.answer_later(fn -> Steward.speak(line) end, &{:voice_spoken, attempt, kind, &1})
    state
  end

  defp perform({:start_vamp, page_ref, gives}, state, _now) do
    Steward.answer_later(fn -> Steward.vamp(gives) end, &{:vamped, page_ref, &1})
    state
  end

  defp perform({:enqueue_track, page_ref, gives, gives_landed_at}, state, _now) do
    code = state.room.slug

    Thereish.Foley.ScoreQueue.enqueue(self(), page_ref, gives,
      on_start: fn ->
        log_music_event(code, page_ref, "score started", gives_landed_at)
      end
    )

    state
  end

  defp perform({:start_title, page_ref, gives}, state, _now) do
    Steward.answer_later(fn -> Steward.title_track(gives) end, &{:titled, page_ref, &1})
    state
  end

  defp perform({:look_up_track, page_ref, gives}, state, now),
    do: follow_up(state, {:track_looked_up, page_ref, cached_track(gives)}, now)

  defp perform({:cache_track, gives, track}, state, _now) do
    Thereish.Steward.TrackCache.put(gives, track)
    state
  end

  defp perform({:record_never, path}, state, _now) do
    {:ok, _} = Store.record_never(state.room.id, path)
    state
  end

  defp perform({:log, level, message}, state, _now) do
    Logger.log(level, message)
    state
  end

  defp perform({:log, _page_ref, {:title_failure, reason}, _landed_at}, state, _now) do
    Logger.warning("Scribe titling failed for room #{state.room.slug}: #{inspect(reason)}")
    state
  end

  defp perform({:log, page_ref, event, gives_landed_at}, state, _now) do
    log_music_event(state.room.slug, page_ref, event, gives_landed_at)
    state
  end

  # A closed Page goes into the Chronicle from this process rather than from a
  # task: it is a handful of rows to the same Postgres the Seats came out of,
  # and a Page that closed while the write was still in flight elsewhere would
  # be a Page that could go missing.
  #
  # A write that fails is logged and swallowed. Losing the record of a Page is
  # bad; taking the Room down in front of the couple, and losing the Page they
  # are looking at along with it, is worse.
  defp perform({:write_chronicle, entry}, state, now) do
    {:ok, page} = Chronicle.write(state.room.id, entry)

    _ = Experiments.record_outcome(state.room.id, page, entry)

    Scribe.write_about(state.room, page)

    follow_up(state, {:chronicle_written, page.id}, now)
  rescue
    error ->
      Logger.error("the Chronicle could not be written: #{Exception.message(error)}")
      state
  end

  # A write that fails is logged and swallowed, like the Page it lands on.
  defp perform({:write_page, page_id, write}, state, _now) do
    write_onto(page_id, write, state)
    state
  rescue
    error ->
      Logger.error("a write onto Page #{page_id} failed: #{Exception.message(error)}")
      state
  end

  defp perform({:record_overrule, overrule}, state, _now) do
    {:ok, _} = Chronicle.record_overrule(state.room.id, overrule)

    {:ok, _} =
      Steward.overrule(
        overrule,
        %{
          closeness: overrule.couple_closeness,
          reasoning: overrule.couple_reasoning,
          quip: overrule.couple_quip
        }
      )

    state
  rescue
    error ->
      Logger.error("the overrule could not be recorded: #{Exception.message(error)}")
      state
  end

  defp perform({:record_fairness_tap, tap_data}, state, _now) do
    {:ok, _} = Chronicle.record_fairness_tap(state.room.id, tap_data)
    state
  rescue
    error ->
      Logger.error("the fairness tap could not be recorded: #{Exception.message(error)}")
      state
  end

  defp write_onto(page_id, {:mask, seat_id, mask}, _state),
    do: Chronicle.update_page_mask(page_id, seat_id, mask)

  defp write_onto(page_id, {:vamp, meta}, _state), do: Chronicle.replace_page_vamp(page_id, meta)

  defp write_onto(page_id, {:music, meta}, _state),
    do: Chronicle.replace_page_music(page_id, meta)

  defp write_onto(page_id, {:bookends_tap, tap_data}, state) do
    {:ok, _} =
      Experiments.record_bookends_tap(state.room.id, Map.put(tap_data, :page_id, page_id))
  end

  defp cached_track(gives) do
    case Thereish.Steward.TrackCache.get(gives) do
      {:ok, track} -> track
      _ -> nil
    end
  end

  defp members(room), do: Thereish.Foley.Repertoire.members(room.id)

  # Pacing reads no configuration, so the Room reads it once, when it opens.
  defp durations do
    %{
      beat: Application.fetch_env!(:thereish, :reveal_beat_ms),
      hold: Application.fetch_env!(:thereish, :reveal_hold_ms),
      assayer: Application.fetch_env!(:thereish, :assayer_escalation_ms),
      author: Application.fetch_env!(:thereish, :author_escalation_ms)
    }
  end

  # The moment Play is told about: the monotonic clock, which a test can
  # freeze, and the wall clock.
  defp now, do: %{ms: now_ms(), at: wall_clock()}

  defp now_ms do
    case Application.get_env(:thereish, :now_ms) do
      fun when is_function(fun, 0) -> fun.()
      _ -> System.monotonic_time(:millisecond)
    end
  end

  defp wall_clock, do: DateTime.utc_now()

  defp verdict_event({:ok, verdict}), do: {:verdict_received, verdict}

  # The Assayer failing is a rule, not an exception: the game says it has no
  # verdict and the call goes to the players.
  defp verdict_event({:error, _reason}), do: {:verdict_unavailable, %{}}

  defp broadcast(slug, message \\ :room_changed) do
    Phoenix.PubSub.broadcast(Thereish.PubSub, Thereish.Rooms.topic(slug), message)
  end

  # Device tokens are the browser's business and never leave this module.
  defp public(%Seat{} = seat), do: %{id: seat.id, name: seat.name}

  @doc """
  Logs a music event carrying the Room's Code, Page reference, event name,
  and milliseconds since Gives landed.
  """
  def log_music_event(code, page_ref, event, gives_landed_at \\ nil)

  def log_music_event(code, page_ref, {fail_tag, reason}, gives_landed_at)
      when fail_tag in [:failure, :vamp_failure] do
    prefix = if fail_tag == :vamp_failure, do: "vamp failure", else: "failure"

    log_music_event(code, page_ref, "#{prefix} with reason: #{inspect(reason)}", gives_landed_at)
  end

  def log_music_event(code, page_ref, event, gives_landed_at) when is_binary(event) do
    elapsed = elapsed_ms(gives_landed_at)
    ref_str = format_page_ref(page_ref)

    msg = "Foley music for room #{code} (page #{ref_str}): #{event} (+#{elapsed}ms)"

    if String.contains?(event, "failure") do
      Logger.warning(msg)
    else
      Logger.info(msg)
    end

    :ok
  end

  defp elapsed_ms(time) when is_integer(time) do
    max(0, System.monotonic_time(:millisecond) - time)
  end

  defp elapsed_ms(_), do: 0

  defp format_page_ref(ref) when is_binary(ref), do: ref
  defp format_page_ref(ref), do: inspect(ref)

  defp has_chronicle?(state) do
    Chronicle.has_pages?(state.room.id)
  end
end
