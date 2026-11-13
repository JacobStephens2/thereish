defmodule Thereish.RevealFixtures do
  @moduledoc "A reveal built through Game and Pacing, with an explicit clock."
  alias Thereish.{Chronicle.Document, Game, Rooms.Pacing}

  def now(ms), do: %{ms: ms, at: DateTime.add(~U[2026-10-03 20:00:00Z], ms, :millisecond)}

  def scenarios do
    for count <- 2..Thereish.Steward.seat_cap(),
        opts <- [
          [],
          [calls: true],
          [split: true],
          [ungraded: true],
          [closeness: 95],
          [calls: true, split: true, sequence: [stagger: 1, cap: 2, settle: 1]]
        ],
        do: [count: count] ++ opts
  end

  def perform(opts \\ []) do
    seats =
      ~w(Mara Bram Esme Cole Sid Rafe Ada Ida)
      |> Enum.take(Keyword.get(opts, :count, 2))
      |> Enum.map(&%{id: &1, name: &1})

    game =
      Game.init(
        seat_limit: Thereish.Steward.seat_cap(),
        seats: seats,
        page: %Document{bookends: ~w(lantern harbour)}
      )

    game =
      Enum.reduce(Enum.zip(seats, ~w(cairn beacon wharf signal torch lamp anchor buoy)), game, fn
        {seat, word}, game ->
          move(game, {:bridge_committed, %{seat_id: seat.id, bridge: word}})
      end)

    game =
      if opts[:calls] do
        Enum.reduce(seats, game, &move(&2, {:call_made, %{seat_id: &1.id, band: :close}}))
      else
        game
      end

    game = if opts[:late], do: move(game, {:seat_joined, %{id: "late", name: "Late"}}), else: game

    event =
      if opts[:ungraded] do
        {:verdict_unavailable, %{}}
      else
        meta = if opts[:split], do: %{forward: 31, reverse: 78, spread: 47}, else: %{}

        {:verdict_received,
         %{
           closeness: Keyword.get(opts, :closeness, 83),
           reasoning: "because",
           furthest: ~w(cairn beacon),
           meta: meta
         }}
      end

    revealed = move(game, event)

    durations = %{
      hold: Keyword.get(opts, :hold, 1),
      sequence: Keyword.get(opts, :sequence, stagger: 260, cap: 1_400, settle: 900)
    }

    {pacing, effects} = Pacing.moved(Pacing.new(durations), game, revealed, now(0))
    %{pacing: pacing, game: revealed, effects: effects, room: snapshot(pacing, revealed, 0)}
  end

  def move(game, event) do
    {:ok, game, _} = Game.apply(game, event)
    game
  end

  def snapshot(pacing, game, ms),
    do: Map.merge(Game.view(game, nil), Pacing.view(pacing, game, now(ms)))
end
