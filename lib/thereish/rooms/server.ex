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

  ## Time is Pacing's

  The Beat, the reveal hold, both escalation ladders and when each part of a
  Page happened are rules about time, and they live in
  `Thereish.Rooms.Pacing`. This process tells Pacing what happened and when,
  and performs what it asks: a timer, some Game events, a broadcast.
  """
  use GenServer, restart: :permanent

  require Logger

  alias Thereish.Chronicle
  alias Thereish.Experiments
  alias Thereish.Foley.Occupancy
  alias Thereish.Foley.Voice
  alias Thereish.Game
  alias Thereish.Rooms.Pacing
  alias Thereish.Rooms.Pages
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
        pacing: Pacing.new(durations()),
        pages: Pages.new(),
        occupancy: Occupancy.new(Thereish.Foley.Repertoire.members(room.id)),
        voice: Voice.new(),
        prologue: nil
      }

      # A Room that comes back with every Seat taken is a Page already open, so
      # Pacing is told about the Game it starts at as a move onto it.
      {:ok, pace(state, &Pacing.moved(&1, game, game, now()))}
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
    with :ok <- Pacing.may_advance(state.pacing, now()),
         {:ok, game, effects} <-
           Game.apply(state.game, {:attempt_advanced, %{seat_id: seat_id}}) do
      {:reply, :ok, advance(state, game, effects)}
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

  # Nothing is reset until the Game accepts it: a late tap from a second phone,
  # after the Author has already written the Page, must leave that Page's
  # music and times alone.
  def handle_call({:reset_gives, seat_id}, _from, state) do
    case Game.apply(state.game, {:gives_reset, %{seat_id: seat_id}}) do
      {:ok, game, effects} ->
        state =
          state
          |> Map.update!(:pacing, &Pacing.gives_reset/1)
          |> Map.update!(:occupancy, &Occupancy.gives_reset/1)
          |> Map.update!(:pages, &Pages.gives_reset/1)

        {:reply, :ok, advance(state, game, effects)}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:next_page, seat_id}, _from, state) do
    with :ok <- Pacing.may_advance(state.pacing, now()) do
      case Game.apply(state.game, {:next_page, %{seat_id: seat_id}}) do
        {:ok, game, effects} ->
          # A closed Page must not vanish if Foley is still speaking when the
          # couple tap next: Voice releases whatever Page it is holding, and
          # its write releases what Pages held for it. Only then may Pages
          # forget the Page in play.
          state = voice(state, &Voice.page_turned/1)

          members = Thereish.Foley.Repertoire.members(state.room.id)

          new_state =
            state
            |> Map.update!(:pacing, &Pacing.page_turned/1)
            |> Map.update!(:pages, &Pages.page_turned/1)
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

          {:reply, :ok, voice(state, &Voice.speaker_claimed(&1, voice_table(state)))}

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

        {:reply, :ok, voice(state, &Voice.speaker_claimed(&1, voice_table(state)))}

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
    {:reply, Voice.clip(state.voice, attempt, kind, voice_table(state)), state}
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
      |> Map.merge(Pacing.view(state.pacing, state.game, now()))
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

    {:reply, view, state}
  end

  # Pacing decides whether the Verdict is held for the Beat, applied or
  # dropped; Voice hears it as it arrives, so its line is ready by the reveal.
  @impl true
  def handle_info({:assayed, event}, state) do
    {:noreply, state |> verdict_heard(event) |> pace(&Pacing.assayed(&1, event))}
  end

  def handle_info({:voice_spoken, attempt, kind, {:ok, result}}, state) do
    {:noreply, voice(state, &Voice.spoken(&1, attempt, kind, {:ok, result}, voice_table(state)))}
  end

  # The failure metadata reads the Steward's adapter config, so it is made here
  # and Voice decides where it goes.
  def handle_info({:voice_spoken, attempt, kind, {:error, reason}}, state) do
    failure = {:error, Steward.voice_failure(reason)}
    {:noreply, voice(state, &Voice.spoken(&1, attempt, kind, failure, voice_table(state)))}
  end

  def handle_info({:pacing, name, token}, state) do
    {:noreply, pace(state, &Pacing.elapsed(&1, name, token, now()))}
  end

  # A superseded, timed-out or duplicate Author changes nothing.
  def handle_info({:author_completed, ref, result}, state) do
    case Pacing.author_answered(state.pacing, ref) do
      {:current, pacing} ->
        {:noreply, apply_events(%{state | pacing: pacing}, [author_event(result, state)])}

      :stale ->
        {:noreply, state}
    end
  end

  # Every Foley result goes to the Occupancy, which decides whether it still
  # belongs to the Page in play.
  def handle_info({tag, page_ref, result}, state) when tag in [:vamped, :scored, :titled] do
    kind = %{vamped: :vamp, scored: :track, titled: :title}[tag]
    {:noreply, occupy(state, &Occupancy.arrived(&1, page_ref, {kind, result}, closed?(state)))}
  end

  # A Mask for the Gives in play is the Game's to accept, whatever it is. One
  # for Gives already past only adds something if it was drawn. Either way,
  # Pages decides which Chronicle Page it lands on.
  def handle_info({:mask_landed, seat_id, giving_ref, result}, state) do
    mask =
      case result do
        {:ok, mask} when is_map(mask) -> Map.delete(mask, :bytes)
        _ -> :dot
      end

    cond do
      giving_ref == Pages.giving(state.pages) ->
        case Game.apply(state.game, {:mask_landed, %{seat_id: seat_id, mask: mask}}) do
          {:ok, game, effects} ->
            state = advance(state, game, effects)
            {:noreply, write_page(state, giving_ref, {:mask, seat_id, mask})}

          {:error, _reason} ->
            {:noreply, state}
        end

      is_map(mask) ->
        {state, wrote?} = run_pages(state, &Pages.write(&1, giving_ref, {:mask, seat_id, mask}))
        if wrote?, do: broadcast(state.room.slug)
        {:noreply, state}

      true ->
        {:noreply, state}
    end
  end

  defp author_event({:ok, result}, state) do
    {:page_written,
     %{
       bookends: result.bookends,
       from: result[:from],
       meta: result.meta,
       full_table: state.room.full_table
     }}
  end

  defp author_event({:error, reason}, _state) do
    {:author_failed, %{reason: format_author_error(reason)}}
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
      %{state | game: game}
      |> pace(&Pacing.moved(&1, old_game, game, now()))

    state = Enum.reduce(effects, state, &perform/2)
    state = voice(state, &Voice.table_moved(&1, voice_table(state)))

    broadcast(state.room.slug)

    state
  end

  defp perform(:beat, state), do: pace(state, &Pacing.beat_owed(&1, now()))

  # A closed Page goes into the Chronicle from this process rather than from a
  # task: it is a handful of rows to the same Postgres the Seats came out of,
  # and a Page that closed while the write was still in flight elsewhere would
  # be a Page that could go missing.
  #
  # The Entry takes the Page's experiment arm here, at the close, so a held
  # write still records the arm the Page was played under.
  #
  # Foley for the closing Verdict may still be in flight when this effect
  # runs. ADR-0003 forbids updating the Verdict row, so Voice decides whether
  # the write waits for that result; it comes back as a :commit_chronicle
  # effect, now or later.
  #
  # A write that fails is logged and swallowed. Losing the record of a Page is
  # bad; taking the Room down in front of the couple, and losing the Page they
  # are looking at along with it, is worse.
  defp perform({:chronicle, entry}, state) do
    entry =
      entry
      |> struct!(Occupancy.chronicle_meta(state.occupancy, state.room.music))
      |> struct!(arm: Pages.arm(state.pages) || Experiments.default_arm())
      |> then(&Pacing.stamp(state.pacing, &1))

    state
    |> Map.update!(:pages, &Pages.page_closed/1)
    |> voice(&Voice.page_closed(&1, entry))
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

  # A tap is made on a closed Page, so it belongs to the Page in play, which
  # Voice may not have let into the Chronicle yet.
  defp perform({:bookends_tap, tap_data}, state) do
    write_page(state, Pages.giving(state.pages), {:bookends_tap, tap_data})
  end

  defp perform({:author, request}, state) do
    room = self()
    digest = Chronicle.digest(state.room.id)
    arm = Pages.arm(state.pages) || Steward.assign_arm(state.room.id)
    ref = make_ref()
    page_ref = make_ref()

    gives = extract_give_strings(request)

    gives_landed_at = System.monotonic_time(:millisecond)

    cached = cached_track(gives)

    state =
      state
      |> Map.update!(:pages, &Pages.page_opened(&1, page_ref, arm))
      |> pace(&Pacing.author_asked(&1, ref, now()))
      |> occupy_quietly(
        &Occupancy.page_opened(&1, page_ref, gives, cached, gives_landed_at, state.room.music)
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
    arm = Pages.arm(state.pages) || Experiments.default_arm()
    page = state.game.page
    request = with_prior_quips(request, state)

    Task.Supervisor.start_child(Thereish.Steward.Tasks, fn ->
      send(room, {:assayed, verdict_event(assay(request, page, arm))})
    end)

    pace(state, &Pacing.assayer_asked(&1, now()))
  end

  # Applies a Pacing transition and performs the effects it returns. A timer
  # is never cancelled: one that fires late carries a token Pacing ignores.
  defp pace(state, transition) do
    {pacing, effects} = transition.(state.pacing)
    Enum.reduce(effects, %{state | pacing: pacing}, &perform_pacing_effect/2)
  end

  defp perform_pacing_effect({:timer, name, token, ms}, state) do
    Process.send_after(self(), {:pacing, name, token}, ms)
    state
  end

  defp perform_pacing_effect({:apply, events}, state), do: apply_events(state, events)

  defp perform_pacing_effect(:broadcast, state) do
    broadcast(state.room.slug)
    state
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
    run_pages(state, &Pages.write(&1, page_ref, {:vamp, meta}))
  end

  defp perform_occupancy_effect({:persist_music_meta, page_ref, meta}, state) do
    run_pages(state, &Pages.write(&1, page_ref, {:music, meta}))
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

  # Hands Pages a write onto the Page `ref` names, for callers that broadcast
  # on their own.
  defp write_page(state, ref, write) do
    {state, _wrote?} = run_pages(state, &Pages.write(&1, ref, write))
    state
  end

  # Applies a Pages transition and performs the writes it returns. Answers the
  # new state and whether a Chronicle Page was written.
  defp run_pages(state, transition) do
    {pages, effects} = transition.(state.pages)
    state = Enum.reduce(effects, %{state | pages: pages}, &perform_page_write/2)
    {state, effects != []}
  end

  # A write that fails is logged and swallowed, like the Page it lands on.
  defp perform_page_write({:write, page_id, write}, state) do
    write_onto(page_id, write, state)
    state
  rescue
    error ->
      Logger.error("a write onto Page #{page_id} failed: #{Exception.message(error)}")
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

  # The Room's facts Occupancy is told on each call rather than keeping a copy.
  defp table(state) do
    %{music: state.room.music, closed?: closed?(state)}
  end

  defp closed?(state), do: Game.phase(state.game) == :closed

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
    giving_ref = Pages.giving(state.pages)
    colour = Game.seat_colour(state.game, seat_id)

    Task.Supervisor.start_child(Thereish.Steward.Tasks, fn ->
      try do
        case Steward.draw(give, colour, size: 512) do
          {:ok, mask_data} ->
            mask = Map.delete(mask_data, :bytes)
            send(room, {:mask_landed, seat_id, giving_ref, {:ok, mask}})

          {:error, reason} ->
            Logger.warning(
              "Limner draw failed for seat #{seat_id}: #{inspect(reason, limit: 40)}"
            )

            send(room, {:mask_landed, seat_id, giving_ref, {:error, reason}})
        end
      rescue
        error ->
          Logger.warning("Limner draw crashed for seat #{seat_id}: #{Exception.message(error)}")

          send(room, {:mask_landed, seat_id, giving_ref, {:error, error}})
      catch
        :exit, reason ->
          Logger.warning("Limner draw exited for seat #{seat_id}: #{inspect(reason, limit: 20)}")
          send(room, {:mask_landed, seat_id, giving_ref, {:error, {:exit, reason}}})
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

  # Pacing reads no configuration, so the Room reads it once, when it opens.
  defp durations do
    %{
      beat: Application.fetch_env!(:thereish, :reveal_beat_ms),
      hold: Application.fetch_env!(:thereish, :reveal_hold_ms),
      assayer: Application.fetch_env!(:thereish, :assayer_escalation_ms),
      author: Application.fetch_env!(:thereish, :author_escalation_ms)
    }
  end

  # The moment Pacing is told about: the monotonic clock, which a test can
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

  defp verdict_heard(state, {:verdict_received, verdict}) do
    voice(state, &Voice.verdict_received(&1, verdict, voice_table(state)))
  end

  defp verdict_heard(state, _event), do: state

  # Applies a Voice transition and carries out the effects it returns, in
  # order: a held Chronicle write lands before the voice_ready that follows it.
  defp voice(state, transition) do
    {voice, effects} = transition.(state.voice)
    Enum.reduce(effects, %{state | voice: voice}, &perform_voice_effect/2)
  end

  defp perform_voice_effect({:speak, attempt, kind, line}, state) do
    speak_line(attempt, kind, line)
    state
  end

  defp perform_voice_effect({:broadcast, message}, state) do
    broadcast(state.room.slug, message)
    state
  end

  defp perform_voice_effect({:commit_chronicle, entry}, state), do: commit_chronicle(entry, state)

  defp perform_voice_effect({:log, level, message}, state) do
    Logger.log(level, message)
    state
  end

  # The Room's and the Game's facts Voice is told on each call.
  defp voice_table(state) do
    %{
      attempt: state.game.attempt,
      phase: Game.phase(state.game),
      bookends: state.game.bookends,
      speaker?: speaker?(state),
      quips?: state.room.quips == true
    }
  end

  defp speak_line(attempt, kind, line) do
    room = self()

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
  end

  defp speaker?(state) do
    not is_nil(state.room.speaker) and state.room.speaker != ""
  end

  defp commit_chronicle(entry, state) do
    {:ok, page} = Chronicle.write(state.room.id, entry)

    _ = Experiments.record_outcome(state.room.id, page, entry)

    Scribe.write_about(state.room, page)

    # The outcome is in, so a tap released here finds it.
    {state, _wrote?} = run_pages(state, &Pages.written(&1, page.id))
    state
  rescue
    error ->
      Logger.error("the Chronicle could not be written: #{Exception.message(error)}")
      state
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
