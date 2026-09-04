defmodule MeaningGame.Game do
  @moduledoc """
  The rules, as a pure reducer over a list of Seats.

  Three functions and no I/O: build the initial state, apply an event, project
  what one viewer may see. It starts no timers, opens no sockets, and calls no
  models — a verdict arrives here as an event, never as a call this module
  makes. That is what lets a whole Page be driven in a test as a list of events,
  and it is why the Room, not the Game, owns time.

  Seats are a **list of N**, two by default, never a pair. Every rule that could
  be written for two players is written for the list, so Jackbox-shaped group
  play is a configuration change rather than a rewrite (ADR-0007). Scoring is
  the clearest case: every unordered pair of Seats gets its own closeness and
  the headline number is the mean across them, which at two Seats is one pair
  and nothing special-cased.

  This module knows nothing about devices, browsers, or Postgres. A Seat here is
  just an id and the name its player typed; who is holding it and how they got
  back to it are the Room's problem.

  ## Phase is derived, never stored

  Where a Page has got to is a question about the state rather than a field in
  it: a Room that is not full is `:waiting`, a full Room with a Page is
  `:bridging`, every Bridge in makes it `:assaying`, every pair graded makes it
  `:reveal`. Nothing has to remember to advance it.

  One deliberate departure from the spec's sketch of this module: `apply/2` can
  answer `{:error, reason}`, because whether a Bridge may be written is a rule
  and rules live here.
  """

  # `apply/2` is the name the spec gives this function, and the reducer shape is
  # worth more than the Kernel import it displaces.
  import Kernel, except: [apply: 2]

  alias MeaningGame.Ladder

  @enforce_keys [:seat_limit, :seats]
  defstruct [:seat_limit, :seats, :page, bridges: %{}, verdicts: %{}]

  @type seat :: %{id: String.t(), name: String.t()}
  @type page :: %{id: String.t(), anchors: [String.t()]}

  @typedoc "Two Seat ids, sorted, so both orderings of a pair name one thing."
  @type pair :: [String.t()]

  @typedoc "What the Assayer said about one pair, or that it could not say."
  @type verdict :: %{
          graded?: boolean(),
          closeness: integer() | nil,
          reasoning: String.t() | nil
        }

  @type t :: %__MODULE__{
          seat_limit: pos_integer(),
          seats: [seat()],
          page: page() | nil,
          bridges: %{String.t() => String.t()},
          verdicts: %{pair() => verdict()}
        }

  @type viewer :: String.t() | nil

  @type event ::
          {:seat_joined, seat()}
          | {:bridge_committed, %{seat_id: String.t(), bridge: String.t()}}
          | {:verdict_received, %{pair: pair(), closeness: integer(), reasoning: String.t()}}
          | {:verdict_unavailable, %{pair: pair()}}

  @typedoc """
  What the Room is asked to do next. Effects are descriptions, never actions:
  this module neither waits out a beat nor calls an Assayer, it says that one is
  owed. `:beat` carries no duration for the same reason — how long the theatre
  runs is the Room's business, and a description that carried it would make this
  module read the clock's configuration.
  """
  @type effect ::
          :beat | {:assay, pair(), %{anchors: [String.t()], bridges: [String.t()]}}

  @type error ::
          :room_full
          | :not_bridging
          | :no_such_seat
          | :already_committed
          | :bridge_required
          | :no_verdict_expected

  @doc """
  Builds the state of a Room that holds `seat_limit` Seats, `seats` of them
  already taken, playing `page`.

  Existing Seats are passed in rather than replayed as events, because they come
  from Postgres, where they outlive every process in this system. A Room with no
  Page yet is a Room waiting for one.
  """
  @spec init(keyword()) :: t()
  def init(opts) do
    %__MODULE__{
      seat_limit: Keyword.fetch!(opts, :seat_limit),
      seats: opts |> Keyword.get(:seats, []) |> Enum.map(&seat/1),
      page: Keyword.get(opts, :page)
    }
  end

  @doc """
  Applies one event, returning the next state and whatever the Room now owes.

  A Seat already in the Room joining again is the ordinary rejoin, and is a
  no-op rather than an error — the Room replays `:seat_joined` on every reconnect
  and must not have to remember whether it already did.
  """
  @spec apply(t(), event()) :: {:ok, t(), [effect()]} | {:error, error()}
  def apply(%__MODULE__{} = state, {:seat_joined, seat}) do
    seat = seat(seat)

    cond do
      seated?(state, seat.id) -> {:ok, state, []}
      full?(state) -> {:error, :room_full}
      true -> {:ok, %{state | seats: state.seats ++ [seat]}, []}
    end
  end

  def apply(%__MODULE__{} = state, {:bridge_committed, %{seat_id: seat_id, bridge: bridge}}) do
    bridge = normalize(bridge)

    cond do
      phase(state) != :bridging -> {:error, :not_bridging}
      not seated?(state, seat_id) -> {:error, :no_such_seat}
      committed?(state, seat_id) -> {:error, :already_committed}
      bridge == "" -> {:error, :bridge_required}
      true -> committed(%{state | bridges: Map.put(state.bridges, seat_id, bridge)})
    end
  end

  def apply(%__MODULE__{} = state, {:verdict_received, verdict}) do
    record(state, verdict.pair, %{
      graded?: true,
      closeness: verdict.closeness,
      reasoning: verdict.reasoning
    })
  end

  def apply(%__MODULE__{} = state, {:verdict_unavailable, %{pair: pair}}) do
    record(state, pair, %{graded?: false, closeness: nil, reasoning: nil})
  end

  @doc """
  Projects what one viewer may see: a Seat by its id, or `nil` for a viewer that
  holds no Seat — the stage on the laptop, or a phone still at the name form.

  Everyone gets the same roster, the same Anchors and the same reveal — the
  stage and the phones must never disagree about the Page they are playing. The
  only things that differ are which Seat is the viewer's own and which Bridge it
  wrote, and an uncommitted Bridge is in nobody's view but its author's until
  every Seat has committed.
  """
  @spec view(t(), viewer()) :: map()
  def view(%__MODULE__{} = state, viewer) do
    phase = phase(state)

    %{
      phase: phase,
      seats: Enum.map(state.seats, &seat_view(state, &1, viewer)),
      you: find_seat(state, viewer),
      seat_limit: state.seat_limit,
      open_seats: state.seat_limit - length(state.seats),
      anchors: anchors(state, phase),
      your_bridge: Map.get(state.bridges, viewer),
      reveal: reveal(state, phase)
    }
  end

  # `init`, `apply` and `view` are the whole surface. Everything below is reached
  # through them, including in tests — a rule that can only be seen by asking a
  # question no player can ask is not being tested where it lives.

  # The last Bridge in is the moment the Page turns: the Assayer is asked for
  # every pair at once, and the beat starts alongside rather than after, so the
  # theatre and the grading run in parallel.
  defp committed(state) do
    if phase(state) == :assaying do
      {:ok, state, [:beat | Enum.map(pairs(state), &assay(state, &1))]}
    else
      {:ok, state, []}
    end
  end

  # Nobody sees the Anchors until everybody can: a player alone in the Room with
  # the two words on screen is a player with a head start on the one still
  # typing their name.
  defp anchors(_state, :waiting), do: nil
  defp anchors(state, _phase), do: state.page.anchors

  defp assay(state, pair) do
    {:assay, pair, %{anchors: state.page.anchors, bridges: Enum.map(pair, &state.bridges[&1])}}
  end

  # A pair is graded once. The Room can deliver the same verdict twice — a
  # retry, a message that outlived the Page it was about — and the second one
  # must not be able to change a number the players are already looking at.
  defp record(state, pair, verdict) do
    pair = Enum.sort(pair)

    cond do
      pair not in pairs(state) -> {:error, :no_verdict_expected}
      Map.has_key?(state.verdicts, pair) -> {:ok, state, []}
      phase(state) != :assaying -> {:error, :no_verdict_expected}
      true -> {:ok, %{state | verdicts: Map.put(state.verdicts, pair, verdict)}, []}
    end
  end

  defp phase(state) do
    cond do
      state.page == nil or not full?(state) -> :waiting
      map_size(state.verdicts) == length(pairs(state)) -> :reveal
      map_size(state.bridges) == length(state.seats) -> :assaying
      true -> :bridging
    end
  end

  # Every unordered pair of Seats, each sorted so that a verdict can be filed
  # under one key however the Assayer was asked. Two Seats is one pair.
  defp pairs(state) do
    ids = Enum.map(state.seats, & &1.id)

    for {id, index} <- Enum.with_index(ids), other <- Enum.drop(ids, index + 1) do
      Enum.sort([id, other])
    end
  end

  defp reveal(_state, phase) when phase != :reveal, do: nil

  defp reveal(state, _phase) do
    pairs = Enum.map(pairs(state), &pair_view(state, &1))

    Map.merge(Ladder.read(headline(pairs)), %{
      bridges:
        Enum.map(state.seats, &%{seat_id: &1.id, name: &1.name, bridge: state.bridges[&1.id]}),
      pairs: pairs
    })
  end

  # The Page's number is the mean across the pairs that got one. A pair the
  # Assayer could not grade is shown as ungraded rather than counted as a zero,
  # because "we don't know" is not "you missed".
  defp headline(pairs) do
    case pairs |> Enum.filter(& &1.graded?) |> Enum.map(& &1.closeness) do
      [] -> nil
      graded -> round(Enum.sum(graded) / length(graded))
    end
  end

  # Names and ids come out in roster order rather than in the pair's own sorted
  # order, because the pair is a key and the roster is what people are looking
  # at.
  defp pair_view(state, pair) do
    seats = Enum.filter(state.seats, &(&1.id in pair))
    verdict = state.verdicts[pair]

    Map.merge(Ladder.read(verdict.closeness), %{
      seat_ids: Enum.map(seats, & &1.id),
      names: Enum.map(seats, & &1.name),
      graded?: verdict.graded?,
      reasoning: verdict.reasoning
    })
  end

  defp seat_view(state, seat, viewer) do
    %{
      id: seat.id,
      name: seat.name,
      you?: seat.id == viewer,
      committed?: committed?(state, seat.id)
    }
  end

  defp committed?(state, seat_id), do: Map.has_key?(state.bridges, seat_id)

  defp find_seat(state, seat_id), do: Enum.find(state.seats, &(&1.id == seat_id))

  defp full?(state), do: length(state.seats) >= state.seat_limit

  # A Bridge is one word, and the game says it its own way: what the players are
  # shown side by side should differ in meaning, not in the shift key.
  defp normalize(bridge), do: bridge |> String.trim() |> String.downcase()

  defp seat(%{id: id, name: name}), do: %{id: id, name: name}

  defp seated?(state, seat_id), do: find_seat(state, seat_id) != nil
end
