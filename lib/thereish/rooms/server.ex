defmodule Thereish.Rooms.Server do
  @moduledoc """
  One supervised process per Room, holding that Room's Seats and its Game state.

  Talk to it through `Thereish.Rooms`, never directly. It is the only thing
  that decides who is in the Room; the LiveViews only ask it and render what
  comes back.

  Every Seat it knows about is in Postgres, so a crash restarts it clean:
  `init/1` reloads the Room and its Seats and rebuilds the Game state from them.
  That is also why reconnect is a snapshot rather than a replay — a client that
  went away asks the current state and gets it, and no message it missed
  matters.

  The Page in progress is the exception, and it is a real one: Bridges and
  verdicts live in this process and nowhere else, so a Room that crashes
  mid-Page comes back at the Bookends with both Bridges gone. The Chronicle is
  written when a Page closes, not as it is played, so a crash costs the Page
  that was in flight — never a Page that finished, and never the Seats.

  ## It owns time, and the rules do not

  The rules answer the last commit with two things owed: one assay carrying
  every Bridge, and a beat. This process performs both — a Task for the Assayer,
  a timer for the beat — and holds the verdict that comes back until the beat is
  over. After the reveal is up, it holds advancement the same way: a shared
  deadline every screen reads, which a reconnect cannot restart and a second
  device cannot skip. That is the whole of the reveal's theatre, and it is why
  the Game itself can be driven in a test as a list of events with no clock in
  sight.

  A verdict is never waited on inline. The Room stays answerable while the
  Assayer thinks, because a phone asking what it missed must not be stuck behind
  a model. An Assayer that raises or exits is a verdict the game does not have,
  which is a rule it already knows: the Attempt goes ungraded and the call goes
  to the players.

  ## An Assayer that is slow, rather than absent

  Design law 10 gives the reveal a ceiling: visible activity through four
  seconds, a provisional reading at eight, and at ten the game states it has no
  verdict. This process runs that ladder, because it is made of time. Each step
  moves what every screen says; the last one is not a step but the end of the
  wait — the Verdict still outstanding is recorded as absent and the call goes
  to the couple, which is design law 3's joint authority arriving by the back
  door rather than an invented number.

  The ladder is armed when the Assayer is asked and disarmed when it answers,
  not when the reveal appears. Those differ by the beat, and an Assayer that
  answered in 200 ms is not slow just because the theatre is still running.

  A timer that fires in the same instant a verdict arrives leaves its message in
  the mailbox, where cancelling it cannot reach. That message is harmless, and
  the reason is the mailbox's own order: it was posted before the verdict was,
  so it is read before the verdict is, and long before anything could start a
  fresh ladder for it to be mistaken for. What it finds is a ladder already
  stood down, which is the last `{:escalate, _}` clause below.
  """
  use GenServer, restart: :permanent

  require Logger

  alias Thereish.Chronicle
  alias Thereish.Foley.Occupancy
  alias Thereish.Game
  alias Thereish.Rooms.Room
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
      seats = Store.list_seats(room.id)

      game =
        Game.init(seat_limit: room.seat_limit, seats: seats, full_table: room.full_table)

      state = %{
        slug: slug,
        room: room,
        game: game,
        beat: nil,
        held: [],
        revealed_at: nil,
        reveal_hold: nil,
        opened_at: nil,
        timing: %{gives: %{}, attempts: %{}},
        assayer: nil,
        author: nil,
        current_arm: nil,
        current_page_id: nil,
        current_page_ref: nil,
        recorded_pages: %{},
        occupancy: Occupancy.new(Thereish.Foley.Repertoire.members(room.id)),
        voice_audio: nil,
        voice_meta: %{},
        voice_pending_attempt: nil,
        bookends_pending_attempt: nil,
        pending_chronicle: nil,
        giving_ref: make_ref(),
        prologue: nil
      }

      {:ok, opened(state)}
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

  def handle_call({:commit_bridge, seat_id, bridge}, _from, state) do
    case Game.apply(state.game, {:bridge_committed, %{seat_id: seat_id, bridge: bridge}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:next_attempt, seat_id}, _from, state) do
    with :ok <- reveal_hold_elapsed(state),
         {:ok, game, effects} <-
           Game.apply(state.game, {:attempt_advanced, %{seat_id: seat_id}}) do
      {:reply, :ok, state |> clear_reveal_hold() |> advance(game, effects)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:propose_overrule, seat_id, opts}, _from, state) do
    attrs = Map.new(opts) |> Map.put(:seat_id, seat_id)

    case Game.apply(state.game, {:overrule_proposed, attrs}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:agree_overrule, seat_id}, _from, state) do
    case Game.apply(state.game, {:overrule_agreed, %{seat_id: seat_id}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:decline_overrule, seat_id}, _from, state) do
    case Game.apply(state.game, {:overrule_declined, %{seat_id: seat_id}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:record_fairness_tap, seat_id, label}, _from, state) do
    case Game.apply(state.game, {:fairness_tapped, %{seat_id: seat_id, label: label}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:tap_bookends, seat_id, label}, _from, state) do
    case Game.apply(state.game, {:bookends_tapped, %{seat_id: seat_id, label: label}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:give, seat_id, give}, _from, state) do
    case Game.apply(state.game, {:give_committed, %{seat_id: seat_id, give: give}}) do
      {:ok, game, effects} ->
        state = advance(state, game, effects)
        state = start_mask_task(state, seat_id, give)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:start_page, seat_id}, _from, state) do
    case Game.apply(state.game, {:start_page, %{seat_id: seat_id}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:retry_author, seat_id}, _from, state) do
    case Game.apply(state.game, {:author_retried, %{seat_id: seat_id}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:reset_gives, seat_id}, _from, state) do
    state =
      state
      |> author_answered()
      |> Map.put(:current_page_ref, nil)
      |> Map.update!(:occupancy, &Occupancy.gives_reset/1)
      |> Map.put(:giving_ref, make_ref())
      |> Map.put(:opened_at, nil)
      |> Map.put(:timing, %{gives: %{}, attempts: %{}})

    case Game.apply(state.game, {:gives_reset, %{seat_id: seat_id}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:next_page, seat_id}, _from, state) do
    with :ok <- reveal_hold_elapsed(state) do
      case Game.apply(state.game, {:next_page, %{seat_id: seat_id}}) do
        {:ok, game, effects} ->
          # A closed Page must not vanish if Foley is still speaking when the
          # couple tap next. Flush whatever voice_meta we have (ADR-0003: the
          # Verdict row is written once).
          state = state |> clear_reveal_hold() |> flush_pending_chronicle()

          members = Thereish.Foley.Repertoire.members(state.room.id)

          new_state =
            %{
              state
              | opened_at: nil,
                timing: %{gives: %{}, attempts: %{}},
                voice_audio: nil,
                voice_meta: %{},
                voice_pending_attempt: nil,
                bookends_pending_attempt: nil
            }
            |> Map.put(:current_arm, nil)
            |> Map.put(:current_page_id, nil)
            |> Map.put(:current_page_ref, nil)
            |> Map.put(:giving_ref, make_ref())
            |> Map.update!(:occupancy, &Occupancy.page_turned(&1, members))

          {:reply, :ok, advance(new_state, game, effects)}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:unblind_experiment, seat_id, experiment_id}, _from, state) do
    case Chronicle.record_experiment_unblinding(state.room.id, %{
           experiment_id: experiment_id || "bait_against_plain",
           seat_id: seat_id,
           unblinded_at: DateTime.utc_now(),
           notes: "Deliberate unblinding"
         }) do
      {:ok, _unblinding} ->
        broadcast(state.room.slug)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:claim_speaker, device_token}, _from, state) do
    if state.room.speaker == device_token do
      {:reply, :ok, state}
    else
      case Store.update_room(state.room, %{speaker: device_token}) do
        {:ok, room} ->
          state = %{state | room: room}
          broadcast(state.room.slug)

          state =
            state
            |> maybe_offer_voice()
            |> maybe_start_bookends_voice()

          {:reply, :ok, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:start_sound, device_token}, _from, state) do
    case Store.update_room(state.room, %{speaker: device_token}) do
      {:ok, room} ->
        state = %{state | room: room}

        state =
          if not has_chronicle?(state) and not state.room.prologue_skipped and
               is_nil(state.prologue) do
            %{state | prologue: Thereish.Foley.Prologue.draw_take()}
          else
            state
          end

        broadcast(state.room.slug)

        state =
          state
          |> maybe_offer_voice()
          |> maybe_start_bookends_voice()

        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:skip_prologue, _from, state) do
    case Store.update_room(state.room, %{prologue_skipped: true}) do
      {:ok, room} ->
        state = %{state | room: room, prologue: nil}
        broadcast(state.room.slug)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:play_prologue, _from, state) do
    state = %{state | prologue: Thereish.Foley.Prologue.draw_take()}
    broadcast(state.room.slug)
    {:reply, :ok, state}
  end

  def handle_call({:release_speaker, device_token}, _from, state) do
    if is_nil(device_token) or state.room.speaker == device_token do
      if is_nil(state.room.speaker) do
        {:reply, :ok, state}
      else
        case Store.update_room(state.room, %{speaker: nil}) do
          {:ok, room} ->
            state = %{state | room: room}
            broadcast(state.room.slug)
            {:reply, :ok, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      end
    else
      {:reply, :ok, state}
    end
  end

  def handle_call({:set_quips, enabled}, _from, state) do
    case Store.update_room(state.room, %{quips: enabled}) do
      {:ok, room} ->
        state = %{state | room: room}
        broadcast(state.room.slug)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_full_table, enabled}, _from, state) do
    case Store.update_room(state.room, %{full_table: enabled}) do
      {:ok, room} ->
        game = %{state.game | full_table: enabled == true}
        state = %{state | room: room, game: game}
        broadcast(state.room.slug)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_music, music}, _from, state) do
    music = to_string(music)

    if music in Room.music_modes() do
      case Store.update_room(state.room, %{music: music}) do
        {:ok, room} ->
          state = occupy_quietly(%{state | room: room}, &Occupancy.music_changed(&1, music))
          broadcast(state.room.slug)
          {:reply, :ok, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    else
      {:reply, {:error, :bad_music_setting}, state}
    end
  end

  def handle_call({:next, device_token}, _from, state) do
    speaker_pressed(state, device_token, &Occupancy.next/2)
  end

  def handle_call({:never, device_token}, _from, state) do
    speaker_pressed(state, device_token, &Occupancy.never/2)
  end

  def handle_call({:voice_audio, attempt, kind}, _from, state) do
    kind = voice_kind(kind)

    case {kind, state[:voice_audio]} do
      {kind, %{attempt: ^attempt} = clips}
      when kind in [:bookends, :verdict] and attempt == state.game.attempt ->
        case clips[kind] do
          %{audio: audio, format: format} when is_binary(audio) ->
            {:reply, {:ok, audio, format}, state}

          _ ->
            {:reply, {:error, :not_found}, state}
        end

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call(:in_play?, _from, state) do
    in_play? = Game.phase(state.game) in [:bridging, :assaying, :reveal]
    {:reply, in_play?, state}
  end

  # The snapshot answers how long the Assayer has been thinking, plus the
  # Room facts (speaker?, speaker_claimed?, quips, music, Full table) for the
  # requesting viewer's device token. Device tokens never leave the Room.
  def handle_call({:snapshot, viewer}, from, state) do
    handle_call({:snapshot, viewer, nil}, from, state)
  end

  def handle_call({:snapshot, viewer, device_token}, _from, state) do
    speaker? =
      not is_nil(state.room.speaker) and not is_nil(device_token) and
        state.room.speaker == device_token

    speaker_claimed? = not is_nil(state.room.speaker)

    view =
      state.game
      |> Game.view(viewer)
      |> Map.put(:assayer_step, step(state))
      |> Map.put(:author_step, author_step(state))
      |> Map.put(:speaker?, speaker?)
      |> Map.put(:speaker_claimed?, speaker_claimed?)
      |> Map.put(:quips, state.room.quips)
      |> Map.put(:full_table, state.room.full_table)
      |> Map.put(:music, state.room.music)
      |> Map.put(:quip, state.room.quip)
      |> Map.merge(Occupancy.view(state.occupancy, table(state)))
      |> Map.put(:prologue_skipped, state.room.prologue_skipped)
      |> Map.put(:prologue, state[:prologue])
      |> Map.put(:prologue_script, Thereish.Foley.Prologue.script())
      |> Map.put(:has_chronicle?, has_chronicle?(state))
      |> Map.put(:can_advance?, can_advance?(state))

    {:reply, view, state}
  end

  # A verdict that arrives during the beat waits it out. The players were
  # promised a fixed beat, and an Assayer that answered in 200 ms must not turn
  # the reveal into a flinch. The escalation ladder is stood down either way:
  # this Assayer has answered.
  @impl true
  def handle_info({:assayed, event}, state) do
    state =
      state
      |> answered()
      |> maybe_start_verdict_voice(event)

    if state.beat do
      {:noreply, %{state | held: state.held ++ [event]}}
    else
      {:noreply, apply_events(state, [event])}
    end
  end

  def handle_info({:voice_spoken, attempt, kind, {:ok, result}}, state) do
    kind = voice_kind(kind)

    if attempt == state.game.attempt and kind in [:bookends, :verdict] do
      format = Map.get(result, :format, :mp3)
      state = put_voice_clip(state, attempt, kind, result.audio, format)
      state = clear_voice_pending(state, attempt, kind)

      state =
        if kind == :verdict do
          raw_meta = result[:meta] || %{}
          provider = raw_meta[:provider] || raw_meta["provider"] || "hume"

          voice =
            raw_meta[:voice] || raw_meta["voice"] || raw_meta[:voice_id] || raw_meta["voice_id"] ||
              "default"

          cost =
            raw_meta[:cost_usd] || raw_meta["cost_usd"] || raw_meta[:cost] || raw_meta["cost"]

          latency =
            raw_meta[:latency_ms] || raw_meta["latency_ms"] || raw_meta[:latency] ||
              raw_meta["latency"]

          voice_meta = %{
            "provider" => to_string(provider),
            "voice" => to_string(voice),
            "model" => to_string(raw_meta[:model] || raw_meta["model"] || voice),
            "cost_usd" => cost,
            "latency_ms" => latency
          }

          # The Chronicle is written before anyone hears the voice is ready, so
          # a screen that reads the Page on voice_ready finds it.
          state =
            %{state | voice_meta: Map.put(state.voice_meta, attempt, voice_meta)}
            |> flush_pending_chronicle()

          broadcast(state.room.slug, {:voice_ready, attempt})
          state
        else
          if Game.phase(state.game) == :bridging do
            broadcast(state.room.slug, {:bookends_ready, attempt})
          end

          state
        end

      {:noreply, state}
    else
      Logger.warning(
        "Voice for attempt #{attempt} (#{kind}) arrived after next attempt started (current: #{state.game.attempt}), dropping"
      )

      {:noreply, state}
    end
  end

  def handle_info({:voice_spoken, attempt, kind, {:error, reason}}, state) do
    Logger.warning("Voice synthesis failed for attempt #{attempt} (#{kind}): #{inspect(reason)}")

    state = clear_voice_pending(state, attempt, kind)

    state =
      if voice_kind(kind) == :verdict do
        failure_meta = Thereish.Steward.voice_failure(reason)

        %{state | voice_meta: Map.put(state.voice_meta, attempt, failure_meta)}
        |> flush_pending_chronicle()
      else
        state
      end

    {:noreply, state}
  end

  def handle_info(:beat_over, state) do
    {:noreply, apply_events(%{state | beat: nil, held: []}, state.held)}
  end

  def handle_info(:reveal_hold_over, state) do
    broadcast(state.room.slug)
    {:noreply, %{state | reveal_hold: nil}}
  end

  # Ten seconds is where the game stops waiting and says so. The Verdict is
  # recorded as absent, which the rules already answer by revealing without a
  # number and handing the ruling to the couple. A verdict that turns up
  # afterwards changes nothing: an Attempt is graded once.
  def handle_info({:escalate, :unavailable}, %{assayer: %{}} = state) do
    event = {:verdict_unavailable, %{}}

    {:noreply, apply_events(%{state | assayer: nil}, [event])}
  end

  def handle_info({:escalate, step}, %{assayer: assayer} = state) when assayer != nil do
    state = %{state | assayer: %{assayer | step: step, timer: escalate_after(step)}}
    broadcast(state.room.slug)

    {:noreply, state}
  end

  # The Assayer answered between the timer firing and this process reading its
  # message. Nothing to escalate.
  def handle_info({:escalate, _step}, state), do: {:noreply, state}

  def handle_info({:escalate_author, :still_writing}, %{author: author} = state)
      when author != nil do
    state = %{
      state
      | author: %{author | step: :still_writing, timer: escalate_author_after(:still_writing)}
    }

    broadcast(state.room.slug)
    {:noreply, state}
  end

  def handle_info({:escalate_author, :deadline}, %{author: author} = state)
      when author != nil do
    state = author_answered(state)
    event = {:author_failed, %{reason: "timed out"}}
    {:noreply, apply_events(state, [event])}
  end

  def handle_info({:escalate_author, _step}, state), do: {:noreply, state}

  def handle_info({:author_completed, ref, {:ok, result}}, %{author: %{ref: ref}} = state) do
    state = author_answered(state)

    event =
      {:page_written,
       %{
         bookends: result.bookends,
         from: result[:from],
         meta: result.meta,
         full_table: state.room.full_table
       }}

    {:noreply, apply_events(state, [event])}
  end

  def handle_info({:author_completed, ref, {:error, reason}}, %{author: %{ref: ref}} = state) do
    state = author_answered(state)
    friendly_reason = format_author_error(reason)
    event = {:author_failed, %{reason: friendly_reason}}
    {:noreply, apply_events(state, [event])}
  end

  # Stale, duplicate, or superseded author tasks change nothing
  def handle_info({:author_completed, _ref, _result}, state), do: {:noreply, state}

  # Every Foley result goes to the Occupancy, which decides whether it still
  # belongs to the Page in play.
  def handle_info({tag, page_ref, result}, state) when tag in [:vamped, :scored, :titled] do
    kind = %{vamped: :vamp, scored: :track, titled: :title}[tag]
    {:noreply, occupy(state, &Occupancy.arrived(&1, page_ref, {kind, result}, closed?(state)))}
  end

  def handle_info({:mask_landed, seat_id, giving_ref, page_ref, result}, state) do
    current_giving? = is_nil(giving_ref) or state[:giving_ref] == giving_ref

    mask =
      case result do
        {:ok, mask_data} when is_map(mask_data) -> Map.delete(mask_data, :bytes)
        mask_data when is_map(mask_data) -> Map.delete(mask_data, :bytes)
        :dot -> :dot
        {:error, _reason} -> :dot
        _ -> :dot
      end

    if current_giving? do
      case Game.apply(state.game, {:mask_landed, %{seat_id: seat_id, mask: mask}}) do
        {:ok, game, effects} ->
          state = advance(state, game, effects)

          page_id = page_id(state, page_ref) || page_id(state, state.current_page_ref)

          if not is_nil(page_id) do
            Chronicle.replace_page_masks(page_id, game.masks)
          end

          {:noreply, state}

        {:error, _reason} ->
          {:noreply, state}
      end
    else
      page_id = page_id(state, page_ref)

      if not is_nil(page_id) and is_map(mask) do
        Chronicle.update_page_mask(page_id, seat_id, mask)
        broadcast(state.room.slug)
      end

      {:noreply, state}
    end
  end

  def handle_info({:mask_landed, seat_id, giving_ref, result}, state) do
    handle_info({:mask_landed, seat_id, giving_ref, nil, result}, state)
  end

  def handle_info({:mask_landed, seat_id, result}, state) do
    handle_info({:mask_landed, seat_id, nil, nil, result}, state)
  end

  def handle_info({:late_mask, seat_id, mask}, state) do
    handle_info({:mask_landed, seat_id, nil, nil, {:ok, mask}}, state)
  end

  defp format_author_error({:max_tokens, _}), do: "too broad or complex"
  defp format_author_error(:refused), do: "content declined"
  defp format_author_error({:refusal, msg}), do: "declined: #{msg}"
  defp format_author_error(%Req.TransportError{reason: :timeout}), do: "timed out"
  defp format_author_error(%{reason: :timeout}), do: "timed out"
  defp format_author_error(:timeout), do: "timed out"
  defp format_author_error(:unavailable), do: "unavailable"
  defp format_author_error({:exit, _}), do: "process exited"
  defp format_author_error(%RuntimeError{message: msg}), do: msg
  defp format_author_error(reason) when is_binary(reason), do: reason
  defp format_author_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_author_error(reason), do: inspect(reason)

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

  # The rules decide before Postgres hears anything, so a Room that is full costs
  # no write. The id is minted here because the rules need a Seat to rule on.
  defp take_seat(name, device_token, state) do
    id = Ecto.UUID.generate()

    with {:ok, game, effects} <-
           Game.apply(state.game, {:seat_joined, %{id: id, name: name}}),
         {:ok, seat} <- Store.insert_seat(state.room.id, id, name, device_token) do
      {:reply, {:ok, public(seat)}, advance(state, game, effects)}
    else
      {:error, :room_full} -> {:reply, {:error, :room_full}, state}
      {:error, %Ecto.Changeset{}} -> {:reply, {:error, :could_not_join}, state}
      {:error, _reason} -> {:reply, {:error, :could_not_join}, state}
    end
  end

  defp apply_events(state, events) do
    old_phase = Game.phase(state.game)
    old_attempt = state.game.attempt

    new_state =
      Enum.reduce(events, state, fn event, state ->
        case Game.apply(state.game, event) do
          {:ok, game, effects} ->
            advance(state, game, effects)

          # A verdict for a Page that has moved on is nothing to act on and
          # nothing to crash over.
          {:error, _reason} ->
            state
        end
      end)

    new_state =
      if new_state.game.attempt != old_attempt do
        %{new_state | voice_audio: nil}
      else
        new_state
      end

    maybe_arm_reveal_hold(new_state, old_phase)
  end

  # Next or Never, which only the device holding the Speaker may press. Any
  # other device's press is ignored rather than refused.
  defp speaker_pressed(state, device_token, press) do
    if speaking_device?(state, device_token) do
      case press.(state.occupancy, table(state)) do
        {:ok, occupancy, effects} ->
          {state, _wrote?} = perform_occupancy_effects(state, occupancy, effects)
          broadcast(state.room.slug)
          {:reply, :ok, state}

        {:error, :refused} ->
          {:reply, {:error, :refused}, state}
      end
    else
      {:reply, :ok, state}
    end
  end

  defp speaking_device?(state, device_token) do
    not is_nil(state.room.speaker) and not is_nil(device_token) and
      state.room.speaker == device_token
  end

  defp advance(state, game, effects) do
    old_game = state.game

    state =
      if game.attempt != old_game.attempt do
        %{state | voice_audio: nil, bookends_pending_attempt: nil}
      else
        state
      end

    state =
      %{state | game: game}
      |> record_occurrence_times(old_game)
      |> opened()

    state =
      Enum.reduce(effects, state, &perform/2)
      |> maybe_start_bookends_voice()

    broadcast(state.room.slug)

    state
  end

  # A Page starts when it is on screen, not when the Room process booted. The
  # difference is everyone typing their names, which is not the ten to fifteen
  # minutes a Page is supposed to take, and it is this timestamp the couch-night
  # measurement will read.
  defp opened(%{opened_at: nil} = state) do
    if Game.view(state.game, nil).phase == :waiting do
      state
    else
      %{state | opened_at: wall_clock()}
    end
  end

  defp opened(state), do: state

  defp perform(:beat, state) do
    %{state | beat: Process.send_after(self(), :beat_over, beat_ms()), held: []}
  end

  # A closed Page goes into the Chronicle from this process rather than from a
  # task: it is a handful of rows to the same Postgres the Seats came out of,
  # and a Page that closed while the write was still in flight elsewhere would
  # be a Page that could go missing.
  #
  # Foley for the closing Verdict is already in flight when this effect runs.
  # ADR-0003 forbids updating the Verdict row, so the write waits for that
  # result and lands voice_meta on the first insert. next_page flushes whatever
  # is waiting so a closed Page cannot vanish if the couple tap through before
  # the voice returns.
  #
  # A write that fails is logged and swallowed. Losing the record of a Page is
  # bad; taking the Room down in front of the couple, and losing the Page they
  # are looking at along with it, is worse.
  defp perform({:chronicle, entry}, state) do
    entry =
      entry
      |> Map.merge(Occupancy.chronicle_meta(state.occupancy, state.room.music))
      |> attach_timing(state)

    if waiting_for_voice_meta?(state, entry) do
      %{state | pending_chronicle: entry}
    else
      commit_chronicle(entry, state)
    end
  end

  defp perform({:overrule, overrule}, state) do
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

  defp perform({:fairness_tap, tap_data}, state) do
    {:ok, _} = Chronicle.record_fairness_tap(state.room.id, tap_data)
    state
  rescue
    error ->
      Logger.error("the fairness tap could not be recorded: #{Exception.message(error)}")
      state
  end

  defp perform({:bookends_tap, tap_data}, state) do
    tap_data =
      if state[:current_page_id] do
        Map.put(tap_data, :page_id, state.current_page_id)
      else
        tap_data
      end

    {:ok, _} = Chronicle.record_bookends_tap(state.room.id, tap_data)
    state
  rescue
    error ->
      Logger.error("the bookends tap could not be recorded: #{Exception.message(error)}")
      state
  end

  defp perform({:author, request}, state) do
    state = author_answered(state)
    room = self()
    digest = Chronicle.digest(state.room.id)
    page_num = (state.game && state.game.page && state.game.page.id) || nil
    arm = state[:current_arm] || Steward.assign_arm(state.room.id, page_num)
    ref = make_ref()
    page_ref = make_ref()

    gives = extract_give_strings(request)

    now = System.monotonic_time(:millisecond)

    cached = cached_track(gives)

    state =
      state
      |> Map.put(:current_arm, arm)
      |> Map.put(:current_page_ref, page_ref)
      |> waiting_on_author(ref)
      |> occupy_quietly(
        &Occupancy.page_opened(&1, page_ref, gives, cached, now, state.room.music)
      )

    Task.Supervisor.start_child(Thereish.Steward.Tasks, fn ->
      try do
        case Steward.author(request, job: arm, digest: digest) do
          {:ok, result} ->
            send(room, {:author_completed, ref, {:ok, result}})

          {:error, reason} ->
            send(room, {:author_completed, ref, {:error, reason}})
        end
      rescue
        error ->
          send(room, {:author_completed, ref, {:error, error}})
      catch
        :exit, reason ->
          send(room, {:author_completed, ref, {:error, {:exit, reason}}})
      end
    end)

    state
  end

  defp perform({:assay, request}, state) do
    room = self()
    arm = state[:current_arm] || :flash
    page = state.game.page
    request = with_prior_quips(request, state)

    Task.Supervisor.start_child(Thereish.Steward.Tasks, fn ->
      send(room, {:assayed, verdict_event(assay(request, page, arm))})
    end)

    waiting_on(state)
  end

  # Applies an Occupancy transition and performs the effects it returns,
  # broadcasting when what the Room shows has changed.
  defp occupy(state, transition) do
    before = Occupancy.view(state.occupancy, table(state))
    {state, wrote?} = run_occupancy(state, transition)

    if wrote? or Occupancy.view(state.occupancy, table(state)) != before do
      broadcast(state.room.slug)
    end

    state
  end

  # As `occupy/2`, for callers that broadcast on their own.
  defp occupy_quietly(state, transition) do
    {state, _wrote?} = run_occupancy(state, transition)
    state
  end

  # Answers the new state and whether a Chronicle Page was written.
  defp run_occupancy(state, transition) do
    {occupancy, effects} = transition.(state.occupancy)
    perform_occupancy_effects(state, occupancy, effects)
  end

  defp perform_occupancy_effects(state, occupancy, effects) do
    Enum.reduce(effects, {%{state | occupancy: occupancy}, false}, fn effect, {state, wrote?} ->
      {state, wrote_now?} = perform_occupancy_effect(effect, state)
      {state, wrote? or wrote_now?}
    end)
  end

  defp perform_occupancy_effect({:start_vamp, page_ref, gives}, state) do
    start_music_task(page_ref, :vamped, fn -> Steward.vamp(gives) end)
    {state, false}
  end

  defp perform_occupancy_effect({:enqueue_track, page_ref, gives, gives_landed_at}, state) do
    code = state.room.slug

    Thereish.Foley.ScoreQueue.enqueue(self(), page_ref, gives,
      on_start: fn ->
        log_music_event(code, page_ref, "score started", gives_landed_at)
      end
    )

    {state, false}
  end

  defp perform_occupancy_effect({:start_title, page_ref, gives}, state) do
    start_music_task(page_ref, :titled, fn -> Steward.title_track(gives) end)
    {state, false}
  end

  defp perform_occupancy_effect({:look_up_track, page_ref, gives}, state) do
    cached = cached_track(gives)
    run_occupancy(state, &Occupancy.track_looked_up(&1, page_ref, cached))
  end

  defp perform_occupancy_effect({:persist_vamp_meta, page_ref, meta}, state) do
    persist_to_page(state, page_ref, &Chronicle.replace_page_vamp(&1, meta))
  end

  defp perform_occupancy_effect({:persist_music_meta, page_ref, meta}, state) do
    persist_to_page(state, page_ref, &Chronicle.replace_page_music(&1, meta))
  end

  defp perform_occupancy_effect({:cache_track, gives, track}, state) do
    Thereish.Steward.TrackCache.put(gives, track)
    {state, false}
  end

  defp perform_occupancy_effect({:record_never, path}, state) do
    {:ok, _} = Store.record_never(state.room.id, path)
    {state, false}
  end

  defp perform_occupancy_effect({:log, _page_ref, {:title_failure, reason}, _landed_at}, state) do
    Logger.warning("Scribe titling failed for room #{state.room.slug}: #{inspect(reason)}")
    {state, false}
  end

  defp perform_occupancy_effect({:log, page_ref, event, gives_landed_at}, state) do
    log_music_event(state.room.slug, page_ref, event, gives_landed_at)
    {state, false}
  end

  # Writes onto the Chronicle Page a Page ref names, once that Page is recorded.
  defp persist_to_page(state, page_ref, write) do
    case page_id(state, page_ref) do
      nil ->
        {state, false}

      page_id ->
        write.(page_id)
        {state, true}
    end
  end

  defp cached_track(gives) do
    case Thereish.Steward.TrackCache.get(gives) do
      {:ok, track} -> track
      _ -> nil
    end
  end

  # The Room's facts Occupancy is told on each call rather than keeping a copy.
  defp table(state) do
    %{music: state.room.music, closed?: closed?(state)}
  end

  defp closed?(state), do: Game.phase(state.game) == :closed

  # The Chronicle Page a Page ref names: one recorded already, or the Page in
  # play once its own write has landed.
  defp page_id(_state, nil), do: nil

  defp page_id(state, page_ref) do
    Map.get(state.recorded_pages, page_ref) ||
      if page_ref == state.current_page_ref, do: state.current_page_id
  end

  defp start_music_task(page_ref, tag, fun) do
    room_pid = self()

    Task.Supervisor.start_child(Thereish.Steward.Tasks, fn ->
      try do
        case fun.() do
          {:ok, result} ->
            send(room_pid, {tag, page_ref, {:ok, result}})

          {:error, reason} ->
            send(room_pid, {tag, page_ref, {:error, reason}})
        end
      rescue
        error ->
          send(room_pid, {tag, page_ref, {:error, error}})
      catch
        :exit, reason ->
          send(room_pid, {tag, page_ref, {:error, {:exit, reason}}})
      end
    end)
  end

  defp start_mask_task(state, seat_id, give) do
    room = self()
    giving_ref = state[:giving_ref]
    page_ref = state.current_page_ref
    colour = Game.seat_colour(state.game, seat_id)

    Task.Supervisor.start_child(Thereish.Steward.Tasks, fn ->
      try do
        case Steward.draw(give, colour, size: 512) do
          {:ok, mask_data} ->
            mask = Map.delete(mask_data, :bytes)
            send(room, {:mask_landed, seat_id, giving_ref, page_ref, {:ok, mask}})

          {:error, reason} ->
            Logger.warning(
              "Limner draw failed for seat #{seat_id}: #{inspect(reason, limit: 40)}"
            )

            send(room, {:mask_landed, seat_id, giving_ref, page_ref, {:error, reason}})
        end
      rescue
        error ->
          Logger.warning("Limner draw crashed for seat #{seat_id}: #{Exception.message(error)}")

          send(room, {:mask_landed, seat_id, giving_ref, page_ref, {:error, error}})
      catch
        :exit, reason ->
          Logger.warning("Limner draw exited for seat #{seat_id}: #{inspect(reason, limit: 20)}")
          send(room, {:mask_landed, seat_id, giving_ref, page_ref, {:error, {:exit, reason}}})
      end
    end)

    state
  end

  defp extract_give_strings(request) do
    cond do
      is_map(request) and is_list(request[:gives]) ->
        extract_from_give_list(request[:gives])

      is_map(request) and is_list(request["gives"]) ->
        extract_from_give_list(request["gives"])

      is_list(request) ->
        extract_from_give_list(request)

      true ->
        []
    end
  end

  defp extract_from_give_list(list) do
    Enum.map(list, &Thereish.Steward.Author.give_text/1)
  end

  defp waiting_on_author(state, ref) do
    %{
      state
      | author: %{
          ref: ref,
          step: :writing,
          timer: escalate_author_after(:writing)
        }
    }
  end

  defp author_answered(%{author: nil} = state), do: state

  defp author_answered(%{author: author} = state) do
    if author[:timer], do: Process.cancel_timer(author.timer)
    %{state | author: nil}
  end

  defp escalate_author_after(step) do
    next = next_author_step(step)

    Process.send_after(
      self(),
      {:escalate_author, next},
      author_escalation_ms(next) - author_escalation_ms(step)
    )
  end

  defp next_author_step(:writing), do: :still_writing
  defp next_author_step(:still_writing), do: :deadline

  defp author_escalation_ms(:writing), do: 0

  defp author_escalation_ms(step) do
    :thereish |> Application.fetch_env!(:author_escalation_ms) |> Keyword.fetch!(step)
  end

  defp author_step(%{author: nil}), do: nil
  defp author_step(%{author: %{step: step}}), do: step

  # One assay per Attempt, so the ladder is armed by the asking and there is
  # nothing to keep a set of: what the couple are watching is one reveal and it
  # is now one request.
  defp waiting_on(state) do
    %{state | assayer: %{step: :grading, timer: escalate_after(:grading)}}
  end

  # An Assayer that has answered is not slow, however long the beat still has to
  # run.
  defp answered(%{assayer: nil} = state), do: state

  defp answered(%{assayer: assayer} = state) do
    Process.cancel_timer(assayer.timer)

    %{state | assayer: nil}
  end

  defp escalate_after(step) do
    next = next_step(step)

    Process.send_after(self(), {:escalate, next}, escalation_ms(next) - escalation_ms(step))
  end

  defp next_step(:grading), do: :slow
  defp next_step(:slow), do: :unavailable

  defp escalation_ms(:grading), do: 0

  defp escalation_ms(step) do
    :thereish |> Application.fetch_env!(:assayer_escalation_ms) |> Keyword.fetch!(step)
  end

  # What every screen is told about the wait. Nothing once the Assayer has
  # answered — a Page still in its beat is a Page whose grade is in.
  defp step(%{assayer: nil}), do: nil
  defp step(%{assayer: %{step: step}}), do: step

  # An Assayer that blows up has failed to grade, which is a thing the game has
  # a rule for. It is not a thing the Room should die of.
  defp assay(request, page, arm) do
    Steward.assay(request, page, arm)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp with_prior_quips(request, state) do
    Map.put(request, :prior_quips, prior_quips(state))
  end

  defp prior_quips(state) do
    closed = Chronicle.recent_quips(state.room.id, 5)
    in_flight = played_quips(state.game)
    Enum.take(closed ++ in_flight, -5)
  end

  defp played_quips(%{played: played}) when is_list(played) do
    for attempt <- played,
        quip <- attempt_quips(attempt) do
      quip
    end
  end

  defp played_quips(_game), do: []

  defp attempt_quips(%{verdict: %{quip: quip}}) when is_binary(quip) and quip != "", do: [quip]
  defp attempt_quips(_attempt), do: []

  # How long the pre-reveal beat runs is the Room's to know, because running it
  # is the Room's job. The rules only say that a beat is owed.
  defp beat_ms, do: Application.fetch_env!(:thereish, :reveal_beat_ms)

  # The pause after a shared reveal, before anyone may advance. Distinct from
  # the beat that runs before the reveal appears.
  defp hold_ms, do: Application.fetch_env!(:thereish, :reveal_hold_ms)

  defp now_ms do
    case Application.get_env(:thereish, :now_ms) do
      fun when is_function(fun, 0) -> fun.()
      _ -> System.monotonic_time(:millisecond)
    end
  end

  defp wall_clock, do: DateTime.utc_now()

  defp record_occurrence_times(state, old_game) do
    now = wall_clock()
    old_phase = Game.phase(old_game)
    new_phase = Game.phase(state.game)
    timing = state[:timing] || %{gives: %{}, attempts: %{}}

    new_give_ids = Map.keys(state.game.gives) -- Map.keys(old_game.gives)

    timing =
      if old_phase != :giving and new_phase == :giving do
        %{timing | gives: %{}}
      else
        timing
      end

    timing =
      Enum.reduce(new_give_ids, timing, fn seat_id, timing ->
        gives = Map.put(timing[:gives] || %{}, seat_id, now)
        %{timing | gives: gives}
      end)

    timing =
      cond do
        old_phase == :bridging and new_phase == :assaying ->
          put_attempt(timing, state.game.attempt, :assaying_started_at, now)

        old_phase == :assaying and new_phase in [:reveal, :closed] ->
          put_attempt(timing, state.game.attempt, :revealed_at, now)

        old_phase == :reveal and new_phase == :bridging ->
          timing
          |> put_attempt(old_game.attempt, :advanced_at, now)
          |> put_attempt(state.game.attempt, :started_at, now)

        old_phase == :writing and new_phase == :bridging ->
          put_attempt(timing, state.game.attempt, :started_at, now)

        true ->
          timing
      end

    %{state | timing: timing}
  end

  defp put_attempt(timing, number, field, now) do
    attempts = timing[:attempts] || %{}
    current = Map.get(attempts, number, %{})

    if Map.has_key?(current, field) do
      timing
    else
      %{timing | attempts: Map.put(attempts, number, Map.put(current, field, now))}
    end
  end

  defp attach_timing(entry, state) do
    timing = state[:timing] || %{gives: %{}, attempts: %{}}
    give_times = timing[:gives] || %{}
    attempt_times = timing[:attempts] || %{}

    gives =
      Enum.map(entry[:gives] || [], fn give ->
        seat_id = give[:seat_id] || give["seat_id"]
        Map.put(give, :arrived_at, Map.get(give_times, seat_id))
      end)

    attempts =
      Enum.map(entry.attempts, fn attempt ->
        times = Map.get(attempt_times, attempt.number, %{})

        attempt
        |> Map.put(:started_at, times[:started_at])
        |> Map.put(:assaying_started_at, times[:assaying_started_at])
        |> Map.put(:revealed_at, times[:revealed_at])
        |> Map.put(:advanced_at, times[:advanced_at])
      end)

    entry
    |> Map.put(:gives, gives)
    |> Map.put(:attempts, attempts)
    |> Map.put(:revealed_at, Thereish.Chronicle.Timing.last_revealed(attempts))
  end

  defp maybe_arm_reveal_hold(state, old_phase) do
    new_phase = Game.phase(state.game)

    if old_phase == :assaying and new_phase in [:reveal, :closed] do
      arm_reveal_hold(state)
    else
      state
    end
  end

  defp arm_reveal_hold(state) do
    if timer = state[:reveal_hold], do: Process.cancel_timer(timer)

    timer =
      case hold_ms() do
        ms when is_integer(ms) and ms > 0 -> Process.send_after(self(), :reveal_hold_over, ms)
        _ -> nil
      end

    %{state | revealed_at: now_ms(), reveal_hold: timer}
  end

  defp clear_reveal_hold(state) do
    if timer = state[:reveal_hold], do: Process.cancel_timer(timer)
    %{state | revealed_at: nil, reveal_hold: nil}
  end

  defp reveal_hold_elapsed(%{revealed_at: nil}), do: :ok

  defp reveal_hold_elapsed(state) do
    if now_ms() - state.revealed_at >= hold_ms() do
      :ok
    else
      {:error, :reveal_held}
    end
  end

  defp can_advance?(state) do
    Game.phase(state.game) in [:reveal, :closed] and reveal_hold_elapsed(state) == :ok
  end

  defp verdict_event({:ok, verdict}), do: {:verdict_received, verdict}

  # The Assayer failing is a rule, not an exception: the game says it has no
  # verdict and the call goes to the players.
  defp verdict_event({:error, _reason}), do: {:verdict_unavailable, %{}}

  defp broadcast(slug, message \\ :room_changed) do
    Phoenix.PubSub.broadcast(Thereish.PubSub, Thereish.Rooms.topic(slug), message)
  end

  defp maybe_start_verdict_voice(state, {:verdict_received, verdict}) do
    if speaker?(state) do
      closeness = verdict[:closeness] || verdict["closeness"]

      band =
        (verdict[:band] && to_string(verdict[:band])) ||
          (closeness && Thereish.Ladder.read(closeness).band |> to_string()) ||
          "miss"

      band_word = band |> String.replace("_", " ")
      quip = (verdict[:quip] || verdict["quip"] || "") |> to_string() |> String.trim()

      line =
        if state.room.quips && quip != "" do
          "#{band_word}. #{quip}"
        else
          band_word
        end

      speak_line(state, :verdict, line)
    else
      state
    end
  end

  defp maybe_start_verdict_voice(state, _event), do: state

  defp maybe_start_bookends_voice(state) do
    bookends = state.game.bookends
    attempt = state.game.attempt

    cond do
      not speaker?(state) ->
        state

      Game.phase(state.game) != :bridging ->
        state

      not is_list(bookends) or bookends == [] ->
        state

      has_voice_clip?(state, :bookends) ->
        state

      state[:bookends_pending_attempt] == attempt ->
        state

      true ->
        speak_line(state, :bookends, Enum.join(bookends, ". "))
    end
  end

  defp maybe_offer_voice(state) do
    attempt = state.game.attempt
    phase = Game.phase(state.game)

    case state.voice_audio do
      %{attempt: ^attempt} = clips ->
        if phase == :bridging and voice_clip?(clips[:bookends]) do
          broadcast(state.room.slug, {:bookends_ready, attempt})
        end

        if phase == :reveal and voice_clip?(clips[:verdict]) do
          broadcast(state.room.slug, {:voice_ready, attempt})
        end

        state

      _ ->
        state
    end
  end

  defp speak_line(state, kind, line) do
    room = self()
    attempt = state.game.attempt

    Task.Supervisor.start_child(Thereish.Steward.Tasks, fn ->
      try do
        case Steward.speak(line) do
          {:ok, result} ->
            send(room, {:voice_spoken, attempt, kind, {:ok, result}})

          {:error, reason} ->
            send(room, {:voice_spoken, attempt, kind, {:error, reason}})
        end
      rescue
        error ->
          send(room, {:voice_spoken, attempt, kind, {:error, error}})
      catch
        :exit, reason ->
          send(room, {:voice_spoken, attempt, kind, {:error, {:exit, reason}}})
      end
    end)

    case kind do
      :verdict -> %{state | voice_pending_attempt: attempt}
      :bookends -> %{state | bookends_pending_attempt: attempt}
    end
  end

  defp speaker?(state) do
    not is_nil(state.room.speaker) and state.room.speaker != ""
  end

  defp voice_kind(kind) when kind in [:bookends, "bookends"], do: :bookends
  defp voice_kind(kind) when kind in [:verdict, "verdict"], do: :verdict
  defp voice_kind(_), do: nil

  defp voice_clip?(%{audio: audio}) when is_binary(audio), do: true
  defp voice_clip?(_), do: false

  defp has_voice_clip?(state, kind) do
    attempt = state.game.attempt

    case state.voice_audio do
      %{attempt: ^attempt} = clips -> voice_clip?(clips[kind])
      _ -> false
    end
  end

  defp put_voice_clip(state, attempt, kind, audio, format) do
    clips =
      case state.voice_audio do
        %{attempt: ^attempt} = existing -> existing
        _ -> %{attempt: attempt, bookends: nil, verdict: nil}
      end

    %{state | voice_audio: Map.put(clips, kind, %{audio: audio, format: format})}
  end

  defp waiting_for_voice_meta?(state, entry) do
    pending = state.voice_pending_attempt

    pending != nil and
      is_nil(Map.get(state.voice_meta, pending)) and
      Enum.any?(entry.attempts, fn attempt -> attempt.number == pending end)
  end

  defp clear_voice_pending(state, attempt, kind) do
    cond do
      kind == :verdict and state.voice_pending_attempt == attempt ->
        %{state | voice_pending_attempt: nil}

      kind == :bookends and state[:bookends_pending_attempt] == attempt ->
        %{state | bookends_pending_attempt: nil}

      true ->
        state
    end
  end

  defp flush_pending_chronicle(%{pending_chronicle: nil} = state), do: state

  defp flush_pending_chronicle(%{pending_chronicle: entry} = state) do
    commit_chronicle(entry, %{state | pending_chronicle: nil})
  end

  defp commit_chronicle(entry, state) do
    entry = attach_voice_meta(entry, state.voice_meta)

    {:ok, page} = Chronicle.write(state.room.id, entry, state.opened_at)

    arm = (entry.author_meta && entry.author_meta["arm"]) || state[:current_arm] || :flash
    _ = Chronicle.record_page_outcome(state.room.id, page, entry, arm)

    Scribe.write_about(state.room, page)

    recorded_pages = Map.put(state.recorded_pages, state.current_page_ref, page.id)

    state
    |> Map.put(:current_page_id, page.id)
    |> Map.put(:recorded_pages, recorded_pages)
  rescue
    error ->
      Logger.error("the Chronicle could not be written: #{Exception.message(error)}")
      state
  end

  defp attach_voice_meta(entry, voice_meta) when is_map(voice_meta) do
    attempts =
      Enum.map(entry.attempts, fn attempt ->
        case Map.get(voice_meta, attempt.number) do
          nil ->
            attempt

          v_meta ->
            verdicts =
              Enum.map(attempt.verdicts, fn verdict ->
                Map.put(verdict, :voice_meta, v_meta)
              end)

            %{attempt | verdicts: verdicts}
        end
      end)

    %{entry | attempts: attempts}
  end

  defp attach_voice_meta(entry, _), do: entry

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
