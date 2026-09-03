defmodule MeaningGame.Game do
  @moduledoc """
  The rules, as a pure reducer over a list of Seats.

  Three functions and no I/O: build the initial state, apply an event, project
  what one viewer may see. It starts no timers, opens no sockets, and calls no
  models — verdicts will arrive here as events, never as calls this module
  makes. That is what lets a whole Page be driven in a test as a list of events,
  and it is why the Room, not the Game, owns time.

  Seats are a **list of N**, two by default, never a pair. Every rule that could
  be written for two players is written for the list, so Jackbox-shaped group
  play is a configuration change rather than a rewrite (ADR-0007).

  This module knows nothing about devices, browsers, or Postgres. A Seat here is
  just an id and the name its player typed; who is holding it and how they got
  back to it are the Room's problem.

  Two deliberate departures from the spec's sketch of this module. `apply/2` can
  answer `{:error, :room_full}`, because whether a Room has a Seat to give is a
  rule and rules live here. And it returns a state rather than `{state,
  effects}`: there is nothing to describe yet, and the effects channel arrives
  with the first effect rather than ahead of it.
  """

  # `apply/2` is the name the spec gives this function, and the reducer shape is
  # worth more than the Kernel import it displaces.
  import Kernel, except: [apply: 2]

  @enforce_keys [:seat_limit, :seats]
  defstruct [:seat_limit, :seats]

  @type seat :: %{id: String.t(), name: String.t()}
  @type t :: %__MODULE__{seat_limit: pos_integer(), seats: [seat()]}
  @type viewer :: String.t() | nil
  @type event :: {:seat_joined, seat()}

  @doc """
  Builds the state of a Room that holds `seat_limit` Seats, `seats` of them
  already taken.

  Existing Seats are passed in rather than replayed as events, because they come
  from Postgres, where they outlive every process in this system.
  """
  @spec init(keyword()) :: t()
  def init(opts) do
    seat_limit = Keyword.fetch!(opts, :seat_limit)
    seats = opts |> Keyword.get(:seats, []) |> Enum.map(&seat/1)

    %__MODULE__{seat_limit: seat_limit, seats: seats}
  end

  @doc """
  Applies one event, returning the next state.

  A Seat already in the Room joining again is the ordinary rejoin, and is a
  no-op rather than an error — the Room replays `:seat_joined` on every reconnect
  and must not have to remember whether it already did.
  """
  @spec apply(t(), event()) :: {:ok, t()} | {:error, :room_full}
  def apply(%__MODULE__{} = state, {:seat_joined, seat}) do
    seat = seat(seat)

    cond do
      seated?(state, seat.id) -> {:ok, state}
      full?(state) -> {:error, :room_full}
      true -> {:ok, %{state | seats: state.seats ++ [seat]}}
    end
  end

  @doc """
  Projects what one viewer may see: a Seat by its id, or `nil` for a viewer that
  holds no Seat — the stage on the laptop, or a phone still at the name form.

  Everyone gets the same roster — the stage and the phones must never disagree
  about who is here — and the only difference is which Seat, if any, is marked
  as the viewer's own.
  """
  @spec view(t(), viewer()) :: map()
  def view(%__MODULE__{} = state, viewer) do
    %{
      seats: Enum.map(state.seats, &%{id: &1.id, name: &1.name, you?: &1.id == viewer}),
      you: find_seat(state, viewer),
      seat_limit: state.seat_limit,
      open_seats: state.seat_limit - length(state.seats)
    }
  end

  # `init`, `apply` and `view` are the whole surface. Everything below is reached
  # through them, including in tests — a rule that can only be seen by asking a
  # question no player can ask is not being tested where it lives.
  defp find_seat(state, seat_id), do: Enum.find(state.seats, &(&1.id == seat_id))

  defp full?(state), do: length(state.seats) >= state.seat_limit

  defp seated?(state, seat_id), do: find_seat(state, seat_id) != nil

  defp seat(%{id: id, name: name}), do: %{id: id, name: name}
end
