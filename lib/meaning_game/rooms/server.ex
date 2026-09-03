defmodule MeaningGame.Rooms.Server do
  @moduledoc """
  One supervised process per Room, holding that Room's Seats and its Game state.

  Talk to it through `MeaningGame.Rooms`, never directly. It is the only thing
  that decides who is in the Room; the LiveViews only ask it and render what
  comes back.

  It owns no durable truth. Every Seat it knows about is in Postgres, so a crash
  restarts it clean: `init/1` reloads the Room and its Seats and rebuilds the
  Game state from them. That is also why reconnect is a snapshot rather than a
  replay — a client that went away asks the current state and gets it, and no
  message it missed matters.
  """
  use GenServer, restart: :permanent

  alias MeaningGame.Game
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
      {:ok, %{room: room, game: Game.init(seat_limit: room.seat_limit, seats: seats)}}
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

  def handle_call({:snapshot, viewer}, _from, state) do
    {:reply, Game.view(state.game, viewer), state}
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

    with {:ok, game} <- Game.apply(state.game, {:seat_joined, %{id: id, name: name}}),
         {:ok, seat} <- Store.insert_seat(state.room.id, id, name, device_token) do
      broadcast(state.room.slug)
      {:reply, {:ok, public(seat)}, %{state | game: game}}
    else
      {:error, :room_full} -> {:reply, {:error, :room_full}, state}
      {:error, %Ecto.Changeset{}} -> {:reply, {:error, :could_not_join}, state}
    end
  end

  defp broadcast(slug) do
    Phoenix.PubSub.broadcast(MeaningGame.PubSub, MeaningGame.Rooms.topic(slug), :room_changed)
  end

  # Device tokens are the browser's business and never leave this module.
  defp public(%Seat{} = seat), do: %{id: seat.id, name: seat.name}
end
