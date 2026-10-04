defmodule Thereish.Rooms.PacingTest do
  @moduledoc """
  The Room's rules about time, driven call by call with an explicit clock and
  asserted on the effects Pacing asks for, its view and `may_advance/2`.

  No test reads a struct field and none of them sleeps: a timer firing is a
  call to `elapsed/4` carrying the token the arming effect handed out.
  """
  use ExUnit.Case, async: true

  alias Thereish.Game
  alias Thereish.Ladder
  alias Thereish.Rooms.Pacing

  @durations %{
    beat: 2_500,
    hold: 5_000,
    assayer: [slow: 4_000, unavailable: 10_000],
    author: [still_writing: 5_000, deadline: 8_000]
  }

  @page %{id: "test-page", bookends: ["lantern", "harbour"]}

  @verdict {:verdict_received,
            %{
              closeness: 0,
              reasoning: "because",
              furthest: ["cairn", "beacon"],
              meta: %{model: "test", prompt_version: "v1", latency_ms: 12, cost_usd: 0.0001}
            }}

  defp pacing(durations \\ @durations), do: Pacing.new(durations)

  defp at(ms), do: %{ms: ms, at: DateTime.add(~U[2026-10-03 20:00:00Z], ms, :millisecond)}

  defp seat(name), do: %{id: "seat-" <> name, name: name}

  defp bridging do
    Game.init(seat_limit: 2, seats: [seat("Melissa"), seat("Jacob")], page: @page)
  end

  defp play(game, event) do
    {:ok, game, _effects} = Game.apply(game, event)
    game
  end

  defp assaying(game \\ bridging(), bridges \\ {"cairn", "beacon"}) do
    {melissa, jacob} = bridges

    game
    |> play({:bridge_committed, %{seat_id: "seat-Melissa", bridge: melissa}})
    |> play({:bridge_committed, %{seat_id: "seat-Jacob", bridge: jacob}})
  end

  defp graded(closeness) do
    {:verdict_received, verdict} = @verdict
    {:verdict_received, %{verdict | closeness: closeness}}
  end

  # The one timer an effect list arms under `name`: its token and its length.
  defp timer(effects, name) do
    [{token, ms}] = for {:timer, ^name, token, ms} <- effects, do: {token, ms}
    {token, ms}
  end

  defp timers(effects), do: for({:timer, _name, _token, _ms} = timer <- effects, do: timer)

  defp view(pacing, game \\ bridging(), now \\ at(0)), do: Pacing.view(pacing, game, now)

  describe "the Beat" do
    test "a Verdict that arrives during the Beat is held and released when it is over" do
      {pacing, effects} = Pacing.beat_owed(pacing(), at(0))
      {beat, 2_500} = timer(effects, :beat)
      {pacing, _effects} = Pacing.assayer_asked(pacing, at(0))

      assert {pacing, []} = Pacing.assayed(pacing, @verdict)

      assert {_pacing, [{:apply, [@verdict]}]} = Pacing.elapsed(pacing, :beat, beat, at(2_500))
    end

    test "a Verdict that arrives after the Beat is applied at once" do
      {pacing, effects} = Pacing.beat_owed(pacing(), at(0))
      {beat, _ms} = timer(effects, :beat)
      {pacing, _effects} = Pacing.assayer_asked(pacing, at(0))

      assert {pacing, []} = Pacing.elapsed(pacing, :beat, beat, at(2_500))
      assert {_pacing, [{:apply, [@verdict]}]} = Pacing.assayed(pacing, @verdict)
    end

    test "an Assayer that answers is never called slow, however long the Beat runs" do
      {pacing, _effects} = Pacing.beat_owed(pacing(%{@durations | beat: 60_000}), at(0))
      {pacing, effects} = Pacing.assayer_asked(pacing, at(0))
      {rung, _ms} = timer(effects, :assayer)

      {pacing, []} = Pacing.assayed(pacing, @verdict)

      assert {pacing, []} = Pacing.elapsed(pacing, :assayer, rung, at(4_000))
      assert view(pacing, assaying()).assayer_step == nil
    end
  end

  describe "the Assayer's ladder" do
    test "steps from grading to slow at its first rung and gives up at its last" do
      game = assaying()
      {pacing, effects} = Pacing.assayer_asked(pacing(), at(0))
      {grading, 4_000} = timer(effects, :assayer)

      assert view(pacing, game).assayer_step == :grading

      {pacing, effects} = Pacing.elapsed(pacing, :assayer, grading, at(4_000))
      {slow, 6_000} = timer(effects, :assayer)
      assert :broadcast in effects
      assert view(pacing, game).assayer_step == :slow

      assert {pacing, [{:apply, [{:verdict_unavailable, %{}}]}]} =
               Pacing.elapsed(pacing, :assayer, slow, at(10_000))

      assert view(pacing, game).assayer_step == nil
    end

    test "a Verdict that arrives after the ladder gave up is dropped" do
      {pacing, effects} = Pacing.assayer_asked(pacing(), at(0))
      {grading, _ms} = timer(effects, :assayer)
      {pacing, effects} = Pacing.elapsed(pacing, :assayer, grading, at(4_000))
      {slow, _ms} = timer(effects, :assayer)
      {pacing, _effects} = Pacing.elapsed(pacing, :assayer, slow, at(10_000))

      assert {_pacing, []} = Pacing.assayed(pacing, @verdict)
    end

    test "a Verdict that arrives with no Assayer asked is dropped, Beat or not" do
      assert {_pacing, []} = Pacing.assayed(pacing(), @verdict)

      {pacing, effects} = Pacing.beat_owed(pacing(), at(0))
      {beat, _ms} = timer(effects, :beat)
      {pacing, []} = Pacing.assayed(pacing, @verdict)

      assert {_pacing, []} = Pacing.elapsed(pacing, :beat, beat, at(2_500))
    end

    test "a rung that fires after its Assayer answered changes nothing" do
      {pacing, effects} = Pacing.assayer_asked(pacing(), at(0))
      {grading, _ms} = timer(effects, :assayer)
      {pacing, _effects} = Pacing.assayed(pacing, @verdict)

      assert {pacing, []} = Pacing.elapsed(pacing, :assayer, grading, at(4_000))
      assert view(pacing, assaying()).assayer_step == nil
    end

    test "a rung from an earlier ladder changes nothing once a fresh one is armed" do
      {pacing, effects} = Pacing.assayer_asked(pacing(), at(0))
      {first, _ms} = timer(effects, :assayer)
      {pacing, _effects} = Pacing.assayed(pacing, @verdict)
      {pacing, _effects} = Pacing.assayer_asked(pacing, at(20_000))

      assert {pacing, []} = Pacing.elapsed(pacing, :assayer, first, at(24_000))
      assert view(pacing, assaying()).assayer_step == :grading
    end
  end

  describe "the Author's ladder" do
    test "steps from writing to still writing and then fails the Page with timed out" do
      {pacing, effects} = Pacing.author_asked(pacing(), make_ref(), at(0))
      {writing, 5_000} = timer(effects, :author)

      assert view(pacing).author_step == :writing

      {pacing, effects} = Pacing.elapsed(pacing, :author, writing, at(5_000))
      {still, 3_000} = timer(effects, :author)
      assert :broadcast in effects
      assert view(pacing).author_step == :still_writing

      assert {pacing, [{:apply, [{:author_failed, %{reason: "timed out"}}]}]} =
               Pacing.elapsed(pacing, :author, still, at(8_000))

      assert view(pacing).author_step == nil
    end

    test "the current request's answer stands the ladder down" do
      ref = make_ref()
      {pacing, effects} = Pacing.author_asked(pacing(), ref, at(0))
      {writing, _ms} = timer(effects, :author)

      assert {:current, pacing} = Pacing.author_answered(pacing, ref)
      assert view(pacing).author_step == nil
      assert {pacing, []} = Pacing.elapsed(pacing, :author, writing, at(5_000))
      assert view(pacing).author_step == nil
      assert :stale = Pacing.author_answered(pacing, ref)
    end

    test "a superseded or unknown request's answer is stale" do
      old = make_ref()
      new = make_ref()
      {pacing, _effects} = Pacing.author_asked(pacing(), old, at(0))
      {pacing, _effects} = Pacing.author_asked(pacing, new, at(1_000))

      assert :stale = Pacing.author_answered(pacing, old)
      assert :stale = Pacing.author_answered(pacing, make_ref())
      assert :stale = Pacing.author_answered(pacing(), old)
      assert {:current, _pacing} = Pacing.author_answered(pacing, new)
    end

    test "a retried Author stands the old ladder down and arms a fresh one" do
      {pacing, effects} = Pacing.author_asked(pacing(), make_ref(), at(0))
      {old, _ms} = timer(effects, :author)
      {pacing, _effects} = Pacing.elapsed(pacing, :author, old, at(5_000))

      {pacing, effects} = Pacing.author_asked(pacing, make_ref(), at(9_000))
      {_fresh, 5_000} = timer(effects, :author)

      assert {pacing, []} = Pacing.elapsed(pacing, :author, old, at(9_500))
      assert view(pacing).author_step == :writing
    end

    test "new Gives stand the Author down" do
      {pacing, effects} = Pacing.author_asked(pacing(), make_ref(), at(0))
      {writing, _ms} = timer(effects, :author)

      pacing = Pacing.gives_reset(pacing)

      assert {pacing, []} = Pacing.elapsed(pacing, :author, writing, at(5_000))
      assert view(pacing).author_step == nil
    end
  end

  describe "the reveal hold" do
    # The Room as it stands the moment a missed Attempt is revealed at 0 ms.
    defp revealed(pacing \\ pacing(), closeness \\ 0) do
      game = assaying()
      revealed = play(game, graded(closeness))
      {pacing, effects} = Pacing.moved(pacing, game, revealed, at(0))

      {pacing, revealed, effects}
    end

    test "refuses advancement one millisecond before its deadline and allows it at it" do
      {pacing, game, _effects} = revealed()

      assert {:error, :reveal_held} = Pacing.may_advance(pacing, at(0))
      assert {:error, :reveal_held} = Pacing.may_advance(pacing, at(4_999))
      refute view(pacing, game, at(4_999)).can_advance?

      assert :ok = Pacing.may_advance(pacing, at(5_000))
      assert view(pacing, game, at(5_000)).can_advance?
    end

    test "is armed on a reveal, with a timer that tells every screen when it ends" do
      {pacing, _game, effects} = revealed()
      {hold, 5_000} = timer(effects, :hold)

      assert {pacing, [:broadcast]} = Pacing.elapsed(pacing, :hold, hold, at(5_000))
      assert :ok = Pacing.may_advance(pacing, at(5_000))
    end

    test "is armed on a closing reveal" do
      {pacing, game, effects} = revealed(pacing(), 100)

      assert Game.phase(game) == :closed
      assert {_token, 5_000} = timer(effects, :hold)
      assert {:error, :reveal_held} = Pacing.may_advance(pacing, at(4_999))
      refute view(pacing, game, at(4_999)).can_advance?
      assert view(pacing, game, at(5_000)).can_advance?
    end

    test "is armed when the Assayer gave up and the reveal has no number" do
      game = assaying()
      ungraded = play(game, {:verdict_unavailable, %{}})
      {pacing, effects} = Pacing.moved(pacing(), game, ungraded, at(0))

      assert {_token, 5_000} = timer(effects, :hold)
      assert {:error, :reveal_held} = Pacing.may_advance(pacing, at(4_999))
    end

    test "a timer that fires before the clock reaches the deadline does not lift it" do
      {pacing, _game, effects} = revealed()
      {hold, _ms} = timer(effects, :hold)

      {pacing, [:broadcast]} = Pacing.elapsed(pacing, :hold, hold, at(4_000))

      assert {:error, :reveal_held} = Pacing.may_advance(pacing, at(4_999))
    end

    test "a later snapshot neither restarts nor skips it" do
      {pacing, game, _effects} = revealed()

      refute view(pacing, game, at(2_000)).can_advance?
      assert {:error, :reveal_held} = Pacing.may_advance(pacing, at(2_000))
      refute view(pacing, game, at(4_999)).can_advance?
      assert view(pacing, game, at(5_000)).can_advance?
    end

    test "is cleared when the Page moves on to the next Attempt" do
      {pacing, game, effects} = revealed()
      {hold, _ms} = timer(effects, :hold)

      next = play(game, {:attempt_advanced, %{seat_id: "seat-Melissa"}})
      {pacing, []} = Pacing.moved(pacing, game, next, at(5_000))

      assert :ok = Pacing.may_advance(pacing, at(5_000))
      assert {pacing, []} = Pacing.elapsed(pacing, :hold, hold, at(5_000))
      refute view(pacing, next, at(5_000)).can_advance?
    end

    test "is cleared when a closed Page turns" do
      {pacing, game, _effects} = revealed(pacing(), 100)

      turned = play(game, {:next_page, %{seat_id: "seat-Melissa"}})
      {pacing, []} = Pacing.moved(pacing, game, turned, at(5_000))

      assert :ok = Pacing.may_advance(pacing, at(5_000))
    end

    test "the next reveal is held from its own moment" do
      {pacing, game, _effects} = revealed()
      next = play(game, {:attempt_advanced, %{seat_id: "seat-Melissa"}})
      {pacing, []} = Pacing.moved(pacing, game, next, at(5_000))

      again = assaying(next, {"stone", "signal"})
      {pacing, []} = Pacing.moved(pacing, next, again, at(6_000))
      revealed = play(again, graded(0))
      {pacing, _effects} = Pacing.moved(pacing, again, revealed, at(7_000))

      assert {:error, :reveal_held} = Pacing.may_advance(pacing, at(11_999))
      assert :ok = Pacing.may_advance(pacing, at(12_000))
    end

    test "is not armed by moves that are not a reveal" do
      game = bridging()
      committed = play(game, {:bridge_committed, %{seat_id: "seat-Melissa", bridge: "cairn"}})

      assert {pacing, []} = Pacing.moved(pacing(), game, committed, at(0))
      assert {pacing, []} = Pacing.moved(pacing, committed, assaying(), at(10))
      assert :ok = Pacing.may_advance(pacing, at(10))
    end

    test "the Beat before the reveal is not the hold" do
      {pacing, _effects} = Pacing.beat_owed(pacing(), at(0))

      assert :ok = Pacing.may_advance(pacing, at(0))
      refute view(pacing, assaying(), at(0)).can_advance?
    end

    test "a hold of zero arms no timer and holds nothing" do
      {pacing, game, effects} = revealed(pacing(%{@durations | hold: 0}))

      assert timers(effects) == []
      assert :ok = Pacing.may_advance(pacing, at(0))
      assert view(pacing, game, at(0)).can_advance?
    end
  end

  describe "when each part of a Page happened" do
    # A Room with one Seat taken, waiting for its second.
    defp waiting, do: Game.init(seat_limit: 2, seats: [seat("Melissa")])

    # Plays `steps`, each an event and the moment it happened, telling Pacing
    # of every move. Answers the last Game and the effects the Game asked for.
    defp drive(pacing, game, steps) do
      Enum.reduce(steps, {pacing, game, []}, fn {event, ms}, {pacing, game, _effects} ->
        {:ok, moved, effects} = Game.apply(game, event)
        {pacing, _pacing_effects} = Pacing.moved(pacing, game, moved, at(ms))
        {pacing, moved, effects}
      end)
    end

    defp give(name, ms), do: {{:give_committed, %{seat_id: "seat-" <> name, give: name}}, ms}

    defp bridge(name, word, ms),
      do: {{:bridge_committed, %{seat_id: "seat-" <> name, bridge: word}}, ms}

    @to_giving [{{:seat_joined, %{id: "seat-Jacob", name: "Jacob"}}, 1_000}]
    @written [{{:page_written, %{bookends: ["lantern", "harbour"]}}, 4_000}]

    # Both Seats Give, at 2 s and 3 s, and the Author writes the Page at 4 s.
    defp written, do: @to_giving ++ [give("Melissa", 2_000), give("Jacob", 3_000)] ++ @written

    # A Page played from an empty table to a closing reveal on its second
    # Attempt: a miss revealed at 9 s, advanced at 20 s, a meld at 29 s.
    defp closed_page(pacing \\ pacing()) do
      drive(
        pacing,
        waiting(),
        written() ++
          [bridge("Melissa", "cairn", 5_000), bridge("Jacob", "beacon", 6_000)] ++
          [{graded(0), 9_000}, {{:attempt_advanced, %{seat_id: "seat-Melissa"}}, 20_000}] ++
          [bridge("Melissa", "stone", 21_000), bridge("Jacob", "stone", 22_000)] ++
          [{graded(Ladder.meld_threshold()), 29_000}]
      )
    end

    defp chronicle_entry(effects) do
      [entry] = for {:chronicle, entry} <- effects, do: entry
      entry
    end

    defp opened_at(pacing), do: Pacing.stamp(pacing, %{gives: [], attempts: []}).opened_at

    test "the Page opened when it left waiting, not when the Room started" do
      game = waiting()
      {pacing, []} = Pacing.moved(pacing(), game, game, at(0))
      assert opened_at(pacing) == nil

      {pacing, _game, _effects} = drive(pacing, game, @to_giving)

      assert opened_at(pacing) == at(1_000).at
    end

    test "the opened time is kept however many moves follow" do
      {pacing, _game, _effects} = closed_page()

      assert opened_at(pacing) == at(1_000).at
    end

    test "a closed Page's entry is stamped with when each part of it happened" do
      {pacing, _game, effects} = closed_page()

      entry = Pacing.stamp(pacing, chronicle_entry(effects))

      assert entry.opened_at == at(1_000).at
      assert entry.revealed_at == at(29_000).at

      assert Map.new(entry.gives, &{&1.seat_id, &1.arrived_at}) == %{
               "seat-Melissa" => at(2_000).at,
               "seat-Jacob" => at(3_000).at
             }

      assert [first, second] = Enum.sort_by(entry.attempts, & &1.number)

      assert Map.take(first, [:started_at, :assaying_started_at, :revealed_at, :advanced_at]) ==
               %{
                 started_at: at(4_000).at,
                 assaying_started_at: at(6_000).at,
                 revealed_at: at(9_000).at,
                 advanced_at: at(20_000).at
               }

      assert Map.take(second, [:started_at, :assaying_started_at, :revealed_at, :advanced_at]) ==
               %{
                 started_at: at(20_000).at,
                 assaying_started_at: at(22_000).at,
                 revealed_at: at(29_000).at,
                 advanced_at: nil
               }
    end

    test "a time already recorded is not overwritten" do
      {pacing, writing, _effects} =
        drive(pacing(), waiting(), @to_giving ++ [give("Melissa", 2_000), give("Jacob", 3_000)])

      [{event, _ms}] = @written
      bridging = play(writing, event)
      {pacing, []} = Pacing.moved(pacing, writing, bridging, at(4_000))

      {pacing, []} = Pacing.moved(pacing, waiting(), writing, at(50_000))
      {pacing, []} = Pacing.moved(pacing, writing, bridging, at(60_000))

      entry =
        Pacing.stamp(pacing, %{gives: [%{seat_id: "seat-Melissa"}], attempts: [%{number: 1}]})

      assert entry.opened_at == at(1_000).at
      assert [%{arrived_at: arrived}] = entry.gives
      assert arrived == at(2_000).at
      assert [%{started_at: started}] = entry.attempts
      assert started == at(4_000).at
    end

    test "a Page with no recorded times is stamped with none" do
      entry =
        Pacing.stamp(pacing(), %{gives: [%{seat_id: "seat-Melissa"}], attempts: [%{number: 1}]})

      assert entry.opened_at == nil
      assert entry.revealed_at == nil
      assert [%{arrived_at: nil}] = entry.gives

      assert [%{started_at: nil, assaying_started_at: nil, revealed_at: nil, advanced_at: nil}] =
               entry.attempts
    end

    test "new Gives forget the opened time and the occurrence times" do
      {pacing, _game, _effects} = drive(pacing(), waiting(), written())

      pacing = Pacing.gives_reset(pacing)

      assert Pacing.stamp(pacing, %{gives: [%{seat_id: "seat-Melissa"}], attempts: [%{number: 1}]}) ==
               %{
                 gives: [%{seat_id: "seat-Melissa", arrived_at: nil}],
                 attempts: [
                   %{
                     number: 1,
                     started_at: nil,
                     assaying_started_at: nil,
                     revealed_at: nil,
                     advanced_at: nil
                   }
                 ],
                 revealed_at: nil,
                 opened_at: nil
               }
    end

    test "turning the Page forgets the times and stands the Author down" do
      {pacing, _effects} = Pacing.author_asked(pacing(), make_ref(), at(0))
      {pacing, _game, _effects} = closed_page(pacing)

      pacing = Pacing.page_turned(pacing)

      assert view(pacing).author_step == nil

      entry =
        Pacing.stamp(pacing, %{gives: [%{seat_id: "seat-Melissa"}], attempts: [%{number: 1}]})

      assert entry.opened_at == nil
      assert [%{arrived_at: nil}] = entry.gives
      assert [%{started_at: nil, revealed_at: nil}] = entry.attempts
    end

    test "the next Page opens from its own moment" do
      {pacing, game, _effects} = closed_page()
      pacing = Pacing.page_turned(pacing)

      turned = play(game, {:next_page, %{seat_id: "seat-Melissa"}})
      {pacing, []} = Pacing.moved(pacing, game, turned, at(40_000))

      assert opened_at(pacing) == at(40_000).at
    end
  end

  describe "the view" do
    test "a fresh Pacing is waiting on nobody, and nothing advances outside a reveal" do
      assert view(pacing()) == %{assayer_step: nil, author_step: nil, can_advance?: false}
    end
  end

  test "a timer name Pacing never armed changes nothing" do
    assert {pacing, []} = Pacing.elapsed(pacing(), :beat, 0, at(0))
    assert {pacing, []} = Pacing.elapsed(pacing, :hold, 0, at(0))
    assert {pacing, []} = Pacing.assayed(pacing, @verdict)
    assert :ok = Pacing.may_advance(pacing, at(0))
  end
end
