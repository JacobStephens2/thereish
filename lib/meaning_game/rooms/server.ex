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

  The rules answer the last commit with two things owed: an assay for every pair
  of Seats, and a beat. This process performs both — a Task each for the
  Assayer, a timer for the beat — and holds every verdict that comes back until
  the beat is over. That is the whole of the reveal's theatre, and it is why the
  Game itself can be driven in a test as a list of events with no clock in
  sight.

  A verdict is never waited on inline. The Room stays answerable while the
  Assayer thinks, because a phone asking what it missed must not be stuck behind
  a model. An Assayer that raises or exits is a verdict the game does not have,
  which is a rule it already knows: the pair goes ungraded and the call goes to
  the players. An Assayer that simply never answers is what the escalation
  ladder is for, and that is not built yet.
  """
  use GenServer, restart: :permanent

  require Logger

  alias MeaningGame.Chronicle
  alias MeaningGame.Game
  alias MeaningGame.Keeper
  alias MeaningGame.Pages
  alias MeaningGame.Rooms.Seat
  alias MeaningGame.Rooms.Store

  def start_link(opts) do
    slug = Keyword.fetch!(opts, :slug)
    GenServer.start_link(__MODULE__, opts, name: via(slug))
  end

  @doc "The registered name of the Room process with this slug."
  def via(slug), do: {:via, Registry, {MeaningGame.Rooms.Registry, slug}}

  @impl true
  def init(opts) do
    slug = Keyword.fetch!(opts, :slug)
    seat_limit = Keyword.fetch!(opts, :seat_limit)

    with {:ok, room} <- Store.get_or_create_room(slug, seat_limit) do
      seats = Store.list_seats(room.id)
      game = Game.init(seat_limit: room.seat_limit, seats: seats, page: Pages.first())
      state = %{room: room, game: game, beat: nil, held: [], opened_at: nil}

      {:ok, opened(state)}
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

  # A fresh Page starts the Room's clock again, because how long a Page took is
  # a fact about that Page and the Game keeps no clock of its own.
  def handle_call({:next_page, seat_id}, _from, state) do
    event = {:page_started, %{seat_id: seat_id, page: Pages.next(state.game.page.id)}}

    case Game.apply(state.game, event) do
      {:ok, game, effects} -> {:reply, :ok, advance(%{state | opened_at: nil}, game, effects)}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:snapshot, viewer}, _from, state) do
    {:reply, Game.view(state.game, viewer), state}
  end

  # A verdict that arrives during the beat waits it out. The players were
  # promised a fixed beat, and an Assayer that answered in 200 ms must not turn
  # the reveal into a flinch.
  @impl true
  def handle_info({:assayed, event}, %{beat: beat} = state) when beat != nil do
    {:noreply, %{state | held: state.held ++ [event]}}
  end

  def handle_info({:assayed, event}, state), do: {:noreply, apply_events(state, [event])}

  def handle_info(:beat_over, state) do
    {:noreply, apply_events(%{state | beat: nil, held: []}, state.held)}
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
    {:ok, _page} = Chronicle.write(state.room.id, entry, state.opened_at)

    state
  rescue
    error ->
      Logger.error("the Chronicle could not be written: #{Exception.message(error)}")
      state
  end

  defp perform({:assay, pair, request}, state) do
    room = self()

    Task.Supervisor.start_child(MeaningGame.Keeper.Tasks, fn ->
      send(room, {:assayed, verdict_event(pair, assay(request))})
    end)

    state
  end

  # An Assayer that blows up has failed to grade, which is a thing the game has
  # a rule for. It is not a thing the Room should die of.
  defp assay(request) do
    Keeper.assay(request)
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  # How long the reveal is held is the Room's to know, because running it is the
  # Room's job. The rules only say that a beat is owed.
  defp beat_ms, do: Application.fetch_env!(:meaning_game, :reveal_beat_ms)

  defp verdict_event(pair, {:ok, verdict}) do
    {:verdict_received, Map.put(verdict, :pair, pair)}
  end

  # The Assayer failing is a rule, not an exception: the game says it has no
  # verdict and the call goes to the players.
  defp verdict_event(pair, {:error, _reason}), do: {:verdict_unavailable, %{pair: pair}}

  defp broadcast(slug) do
    Phoenix.PubSub.broadcast(MeaningGame.PubSub, MeaningGame.Rooms.topic(slug), :room_changed)
  end

  # Device tokens are the browser's business and never leave this module.
  defp public(%Seat{} = seat), do: %{id: seat.id, name: seat.name}
end
