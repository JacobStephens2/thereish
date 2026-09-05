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
  mid-Page comes back at the Anchors with both Bridges gone. The Chronicle is
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
  alias MeaningGame.Pages
  alias MeaningGame.Rooms.Seat
  alias MeaningGame.Rooms.Store
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
      page = Pages.first(room.id)
      game = Game.init(seat_limit: room.seat_limit, seats: seats, page: page)
      current_arm = assign_and_record_arm(room.id, page)

      state = %{
        room: room,
        game: game,
        beat: nil,
        held: [],
        opened_at: nil,
        assayer: nil,
        give_status: nil,
        give_announcement: nil,
        give_failure: nil,
        active_give: nil,
        current_arm: current_arm
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
    give = String.trim(give || "")

    cond do
      is_nil(find_seat(state, seat_id)) ->
        {:reply, {:error, :no_such_seat}, state}

      give == "" ->
        {:reply, {:error, :give_required}, state}

      true ->
        room_pid = self()
        room_id = state.room.id
        slug = state.room.slug
        digest = Chronicle.digest(room_id)

        Task.Supervisor.start_child(MeaningGame.Steward.Tasks, fn ->
          author_give_task(room_pid, give, digest)
        end)

        state =
          state
          |> Map.put(:give_status, %{status: :in_flight, give: give, seat_id: seat_id})
          |> Map.put(:give_failure, nil)

        broadcast(slug)
        {:reply, :ok, state}
    end
  end

  def handle_call({:next_page, seat_id}, _from, state) do
    view = Game.view(state.game, seat_id)

    cond do
      is_nil(view.you) ->
        {:reply, {:error, :no_such_seat}, state}

      view.phase != :closed ->
        {:reply, {:error, :page_open}, state}

      true ->
        draw_result =
          if state[:active_give] do
            case Pages.next(state.game.page.id, state.room.id, give: state[:active_give]) do
              {:ok, next_page} ->
                {:ok, next_page, state}

              {:error, :pool_exhausted} ->
                case Pages.next(state.game.page.id, state.room.id) do
                  {:ok, next_page} -> {:ok, next_page, Map.put(state, :active_give, nil)}
                  {:error, :pool_exhausted} = err -> err
                end
            end
          else
            case Pages.next(state.game.page.id, state.room.id) do
              {:ok, next_page} -> {:ok, next_page, state}
              {:error, :pool_exhausted} = err -> err
            end
          end

        case draw_result do
          {:ok, next_page, state} ->
            current_arm = assign_and_record_arm(state.room.id, next_page)
            state = Map.put(state, :current_arm, current_arm)
            event = {:page_started, %{seat_id: seat_id, page: next_page}}

            case Game.apply(state.game, event) do
              {:ok, game, effects} ->
                state =
                  if state[:give_announcement] &&
                       state.give_announcement[:give] == next_page[:give] do
                    Map.put(state, :give_announcement, nil)
                  else
                    state
                  end

                {:reply, :ok, advance(%{state | opened_at: nil}, game, effects)}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end

          {:error, :pool_exhausted} = error ->
            {:reply, error, state}
        end
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

  # The one thing a snapshot says that the rules did not: how long the Assayer
  # has been thinking. It is the Room's to answer because it is made of time,
  # and the Game keeps no clock.
  def handle_call({:snapshot, viewer}, _from, state) do
    view =
      state.game
      |> Game.view(viewer)
      |> Map.put(:assayer_step, step(state))
      |> Map.put(:provisional_band, provisional_band(state))
      |> Map.put(:give_status, state[:give_status])
      |> Map.put(:give_announcement, state[:give_announcement])
      |> Map.put(:give_failure, state[:give_failure])
      |> Map.put(:active_give, state[:active_give])

    {:reply, view, state}
  end

  # A verdict that arrives during the beat waits it out. The players were
  # promised a fixed beat, and an Assayer that answered in 200 ms must not turn
  # the reveal into a flinch. The escalation ladder is stood down either way:
  # this Assayer has answered.
  @impl true
  def handle_info({:assayed, event}, state) do
    state = answered(state)

    if state.beat do
      {:noreply, %{state | held: state.held ++ [event]}}
    else
      {:noreply, apply_events(state, [event])}
    end
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

  def handle_info({:give_completed, {:ok, pages}, give}, state) do
    state =
      state
      |> Map.put(:active_give, give)
      |> Map.put(:give_status, %{status: :landed, give: give, count: length(pages)})
      |> Map.put(:give_announcement, %{give: give, count: length(pages)})
      |> Map.put(:give_failure, nil)

    broadcast(state.room.slug)
    {:noreply, state}
  end

  def handle_info({:give_completed, {:error, reason}, give}, state) do
    friendly_reason = format_give_error(reason)

    state =
      state
      |> Map.put(:give_status, %{status: :failed, give: give, reason: friendly_reason})
      |> Map.put(:give_failure, %{give: give, reason: friendly_reason})
      |> Map.put(:give_announcement, nil)

    broadcast(state.room.slug)
    {:noreply, state}
  end

  defp author_give_task(room_pid, give, digest) do
    case Pages.author_give(give, digest: digest) do
      {:ok, pages} ->
        send(room_pid, {:give_completed, {:ok, pages}, give})

      {:error, reason} ->
        send(room_pid, {:give_completed, {:error, reason}, give})
    end
  rescue
    e ->
      send(room_pid, {:give_completed, {:error, Exception.message(e)}, give})
  catch
    :exit, reason ->
      send(room_pid, {:give_completed, {:error, inspect(reason)}, give})
  end

  defp format_give_error({:max_tokens, _}), do: "too broad or complex"
  defp format_give_error(:refused), do: "content declined"
  defp format_give_error({:refusal, msg}), do: "declined: #{msg}"
  defp format_give_error(%Req.TransportError{reason: :timeout}), do: "timed out"
  defp format_give_error(%{reason: :timeout}), do: "timed out"
  defp format_give_error(:timeout), do: "timed out"
  defp format_give_error(reason) when is_binary(reason), do: reason
  defp format_give_error(reason) when is_atom(reason), do: to_string(reason)
  defp format_give_error(reason), do: inspect(reason)

  defp find_seat(state, seat_id) do
    Enum.find(state.game.seats, &(&1.id == seat_id))
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
    Enum.reduce(events, state, fn event, state ->
      case Game.apply(state.game, event) do
        {:ok, game, effects} -> advance(state, game, effects)
        # A verdict for a Page that has moved on is nothing to act on and
        # nothing to crash over.
        {:error, _reason} -> state
      end
    end)
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
    {:ok, page} = Chronicle.write(state.room.id, entry, state.opened_at)

    arm = state[:current_arm] || :bait
    _ = Chronicle.record_page_outcome(state.room.id, page, entry, arm)

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
        overrule.anchors,
        overrule.bridges,
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

  defp perform({:assay, request}, state) do
    room = self()
    arm = state[:current_arm] || :bait
    page = state.game.page

    Task.Supervisor.start_child(MeaningGame.Steward.Tasks, fn ->
      send(room, {:assayed, verdict_event(assay(request, page, arm))})
    end)

    waiting_on(state)
  end

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
  defp next_step(:slow), do: :provisional
  defp next_step(:provisional), do: :unavailable

  defp escalation_ms(:grading), do: 0

  defp escalation_ms(step) do
    :meaning_game |> Application.fetch_env!(:assayer_escalation_ms) |> Keyword.fetch!(step)
  end

  # What every screen is told about the wait. Nothing once the Assayer has
  # answered — a Page still in its beat is a Page whose grade is in.
  defp step(%{assayer: nil}), do: nil
  defp step(%{assayer: %{step: step}}), do: step

  # Eight seconds in, the Author's own table reads every Bridge that was written,
  # in roster order — the same set the Assayer was handed.
  defp provisional_band(%{assayer: %{step: :provisional}} = state) do
    bridges = for seat <- state.game.seats, do: Map.get(state.game.bridges, seat.id)

    if bridges != [] and Enum.all?(bridges, &is_binary/1) do
      Pages.provisional_reading(state.game.page, bridges)
    end
  end

  defp provisional_band(_state), do: nil

  # An Assayer that blows up has failed to grade, which is a thing the game has
  # a rule for. It is not a thing the Room should die of.
  defp assay(request, page, arm) do
    Steward.assay(request, page, arm)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  defp assign_and_record_arm(room_id, page) do
    Steward.assign_arm(room_id, page)
  end

  # How long the reveal is held is the Room's to know, because running it is the
  # Room's job. The rules only say that a beat is owed.
  defp beat_ms, do: Application.fetch_env!(:meaning_game, :reveal_beat_ms)

  defp verdict_event({:ok, verdict}), do: {:verdict_received, verdict}

  # The Assayer failing is a rule, not an exception: the game says it has no
  # verdict and the call goes to the players.
  defp verdict_event({:error, _reason}), do: {:verdict_unavailable, %{}}

  defp broadcast(slug) do
    Phoenix.PubSub.broadcast(MeaningGame.PubSub, MeaningGame.Rooms.topic(slug), :room_changed)
  end

  # Device tokens are the browser's business and never leave this module.
  defp public(%Seat{} = seat), do: %{id: seat.id, name: seat.name}
end
