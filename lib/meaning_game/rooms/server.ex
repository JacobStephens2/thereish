defmodule MeaningGame.Rooms.Server do
  @moduledoc """
  One supervised process per Room, holding that Room's Seats and its Game state.

  Talk to it through `MeaningGame.Rooms`, never directly. It is the only thing
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
  over. That is the whole of the reveal's theatre, and it is why the Game itself
  can be driven in a test as a list of events with no clock in sight.

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

  alias MeaningGame.Chronicle
  alias MeaningGame.Game
  alias MeaningGame.Rooms.Seat
  alias MeaningGame.Rooms.Store
  alias MeaningGame.Scribe
  alias MeaningGame.Steward

  def start_link(opts) do
    slug = Keyword.fetch!(opts, :slug)
    GenServer.start_link(__MODULE__, opts, name: via(slug))
  end

  @doc "The registered name of the Room process with this slug."
  def via(slug), do: {:via, Registry, {MeaningGame.Rooms.Registry, slug}}

  @impl true
  def init(opts) do
    slug = Keyword.fetch!(opts, :slug)

    # A Room is created through `MeaningGame.Rooms.create/2` and nowhere else,
    # so a process asked to start for a Code no Room has is a bug upstream, not
    # a Room to bring into being.
    with %{} = room <- Store.get_room(slug) do
      seats = Store.list_seats(room.id)
      game = Game.init(seat_limit: room.seat_limit, seats: seats)

      state = %{
        room: room,
        game: game,
        beat: nil,
        held: [],
        opened_at: nil,
        assayer: nil,
        author: nil,
        current_arm: :flash,
        voice_audio: nil,
        voice_meta: %{}
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
    case Game.apply(state.game, {:attempt_advanced, %{seat_id: seat_id}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
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

  def handle_call({:give, seat_id, give}, _from, state) do
    case Game.apply(state.game, {:give_committed, %{seat_id: seat_id, give: give}}) do
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
    state = author_answered(state)

    case Game.apply(state.game, {:gives_reset, %{seat_id: seat_id}}) do
      {:ok, game, effects} -> {:reply, :ok, advance(state, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:next_page, seat_id}, _from, state) do
    case Game.apply(state.game, {:next_page, %{seat_id: seat_id}}) do
      {:ok, game, effects} ->
        {:reply, :ok,
         advance(%{state | opened_at: nil, voice_audio: nil, voice_meta: %{}}, game, effects)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
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
          {:reply, :ok, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
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

  def handle_call({:set_voice, enabled}, _from, state) do
    case Store.update_room(state.room, %{voice: enabled}) do
      {:ok, room} ->
        state = %{state | room: room}
        broadcast(state.room.slug)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:set_house_loop_only, enabled}, _from, state) do
    case Store.update_room(state.room, %{house_loop_only: enabled}) do
      {:ok, room} ->
        state = %{state | room: room}
        broadcast(state.room.slug)
        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:voice_audio, attempt}, _from, state) do
    case state[:voice_audio] do
      %{attempt: ^attempt, audio: audio, format: format}
      when is_binary(audio) and attempt == state.game.attempt ->
        {:reply, {:ok, audio, format}, state}

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # The snapshot answers how long the Assayer has been thinking, plus the
  # Room facts (speaker?, speaker_claimed?, voice, house_loop_only) for the
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
      |> Map.put(:voice, state.room.voice)
      |> Map.put(:house_loop_only, state.room.house_loop_only)

    {:reply, view, state}
  end

  # A verdict that arrives during the beat waits it out. The players were
  # promised a fixed beat, and an Assayer that answered in 200 ms must not turn
  # the reveal into a flinch. The escalation ladder is stood down either way:
  # this Assayer has answered.
  @impl true
  def handle_info({:assayed, event}, state) do
    state = answered(state)
    maybe_start_voice_task(event, state)

    if state.beat do
      {:noreply, %{state | held: state.held ++ [event]}}
    else
      {:noreply, apply_events(state, [event])}
    end
  end

  def handle_info({:voice_spoken, attempt, {:ok, result}}, state) do
    if attempt == state.game.attempt do
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

      format = Map.get(result, :format, :mp3)

      state = %{
        state
        | voice_audio: %{attempt: attempt, audio: result.audio, format: format},
          voice_meta: Map.put(state.voice_meta, attempt, voice_meta)
      }

      broadcast(state.room.slug, {:voice_ready, attempt})
      {:noreply, state}
    else
      Logger.warning(
        "Voice for attempt #{attempt} arrived after next attempt started (current: #{state.game.attempt}), dropping"
      )

      {:noreply, state}
    end
  end

  def handle_info({:voice_spoken, attempt, {:error, reason}}, state) do
    Logger.warning("Voice synthesis failed for attempt #{attempt}: #{inspect(reason)}")
    {:noreply, state}
  end

  def handle_info(:beat_over, state) do
    {:noreply, apply_events(%{state | beat: nil, held: []}, state.held)}
  end

  # Ten seconds is where the game stops waiting and says so. The Verdict is
  # recorded as absent, which the rules already answer by revealing without a
  # number and handing the ruling to the couple. A verdict that turns up
  # afterwards changes nothing: an Attempt is graded once.
  def handle_info({:escalate, :unavailable}, %{assayer: %{}} = state) do
    {:noreply, apply_events(%{state | assayer: nil}, [{:verdict_unavailable, %{}}])}
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
    event = {:page_written, %{bookends: result.bookends, meta: result.meta}}
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

    with {:ok, game, effects} <- Game.apply(state.game, {:seat_joined, %{id: id, name: name}}),
         {:ok, seat} <- Store.insert_seat(state.room.id, id, name, device_token) do
      {:reply, {:ok, public(seat)}, advance(state, game, effects)}
    else
      {:error, :room_full} -> {:reply, {:error, :room_full}, state}
      {:error, %Ecto.Changeset{}} -> {:reply, {:error, :could_not_join}, state}
    end
  end

  defp apply_events(state, events) do
    old_attempt = state.game.attempt

    new_state =
      Enum.reduce(events, state, fn event, state ->
        case Game.apply(state.game, event) do
          {:ok, game, effects} -> advance(state, game, effects)
          # A verdict for a Page that has moved on is nothing to act on and
          # nothing to crash over.
          {:error, _reason} -> state
        end
      end)

    if new_state.game.attempt != old_attempt do
      %{new_state | voice_audio: nil}
    else
      new_state
    end
  end

  defp advance(state, game, effects) do
    state = Enum.reduce(effects, opened(%{state | game: game}), &perform/2)
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
      %{state | opened_at: DateTime.utc_now()}
    end
  end

  defp opened(state), do: state

  defp perform(:beat, state) do
    %{state | beat: Process.send_after(self(), :beat_over, beat_ms()), held: []}
  end

  # A closed Page goes into the Chronicle before anything else happens, and it
  # goes in from here rather than from a task: it is a handful of rows to the
  # same Postgres the Seats came out of, and a Page that closed while the write
  # was still in flight elsewhere would be a Page that could go missing.
  #
  # A write that fails is logged and swallowed. Losing the record of a Page is
  # bad; taking the Room down in front of the couple, and losing the Page they
  # are looking at along with it, is worse.
  defp perform({:chronicle, entry}, state) do
    entry = attach_voice_meta(entry, state.voice_meta)
    {:ok, page} = Chronicle.write(state.room.id, entry, state.opened_at)

    arm = state[:current_arm] || :bait
    _ = Chronicle.record_page_outcome(state.room.id, page, entry, arm)

    # A Page that is safely in the log gets written about. It happens somewhere
    # else and the Room does not wait: nobody at the couch waits for a
    # paragraph (`MeaningGame.Scribe`).
    Scribe.write_about(state.room, page)

    state
  rescue
    error ->
      Logger.error("the Chronicle could not be written: #{Exception.message(error)}")
      state
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

  defp perform({:author, request}, state) do
    state = author_answered(state)
    room = self()
    digest = Chronicle.digest(state.room.id)
    ref = make_ref()

    Task.Supervisor.start_child(MeaningGame.Steward.Tasks, fn ->
      try do
        case Steward.author(request, job: :flash, digest: digest) do
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

    waiting_on_author(state, ref)
  end

  defp perform({:assay, request}, state) do
    room = self()
    arm = state[:current_arm] || :flash
    page = state.game.page

    Task.Supervisor.start_child(MeaningGame.Steward.Tasks, fn ->
      send(room, {:assayed, verdict_event(assay(request, page, arm))})
    end)

    waiting_on(state)
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
    :meaning_game |> Application.fetch_env!(:author_escalation_ms) |> Keyword.fetch!(step)
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
    :meaning_game |> Application.fetch_env!(:assayer_escalation_ms) |> Keyword.fetch!(step)
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

  # How long the reveal is held is the Room's to know, because running it is the
  # Room's job. The rules only say that a beat is owed.
  defp beat_ms, do: Application.fetch_env!(:meaning_game, :reveal_beat_ms)

  defp verdict_event({:ok, verdict}), do: {:verdict_received, verdict}

  # The Assayer failing is a rule, not an exception: the game says it has no
  # verdict and the call goes to the players.
  defp verdict_event({:error, _reason}), do: {:verdict_unavailable, %{}}

  defp broadcast(slug, message \\ :room_changed) do
    Phoenix.PubSub.broadcast(MeaningGame.PubSub, MeaningGame.Rooms.topic(slug), message)
  end

  defp maybe_start_voice_task({:verdict_received, verdict}, state) do
    if state.room.voice and not is_nil(state.room.speaker) and state.room.speaker != "" do
      closeness = verdict[:closeness] || verdict["closeness"]

      band =
        (verdict[:band] && to_string(verdict[:band])) ||
          (closeness && MeaningGame.Ladder.read(closeness).band |> to_string()) ||
          "miss"

      band_word = band |> String.replace("_", " ")
      quip = (verdict[:quip] || verdict["quip"] || "") |> to_string() |> String.trim()

      line = if quip != "", do: "#{band_word}. #{quip}", else: band_word
      room = self()
      attempt = state.game.attempt

      Task.Supervisor.start_child(MeaningGame.Steward.Tasks, fn ->
        try do
          case Steward.speak(line) do
            {:ok, result} ->
              send(room, {:voice_spoken, attempt, {:ok, result}})

            {:error, reason} ->
              send(room, {:voice_spoken, attempt, {:error, reason}})
          end
        rescue
          error ->
            send(room, {:voice_spoken, attempt, {:error, error}})
        catch
          :exit, reason ->
            send(room, {:voice_spoken, attempt, {:error, {:exit, reason}}})
        end
      end)
    end
  end

  defp maybe_start_voice_task(_event, _state), do: :ok

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
end
