defmodule Thereish.Rooms.RevealScheduleTest do
  use ExUnit.Case, async: true
  alias Thereish.Rooms.Pacing
  import Thereish.RevealFixtures

  test "the short hold includes the written Split reading's last endpoint" do
    %{pacing: pacing, game: game, effects: effects, room: room} = perform(split: true)
    assert %{duration: 1_840, elapsed: 0, steps: steps} = room.reveal_sequence
    assert %{role: :split_text, delay: 1_600, duration: 240} in steps
    assert [{:timer, :hold, _, 1_840}] = effects
    assert {:error, :reveal_held} = Pacing.may_advance(pacing, now(1_839))
    assert :ok = Pacing.may_advance(pacing, now(1_840))
    assert snapshot(pacing, game, 2_000).reveal_sequence.elapsed == 1_840
  end

  test "every applicable endpoint fits the hold, from two through the Seat cap" do
    for count <- 2..Thereish.Steward.seat_cap(),
        opts <- [
          [],
          [calls: true],
          [split: true],
          [ungraded: true],
          [closeness: 95],
          [calls: true, split: true, sequence: [stagger: 1, cap: 2, settle: 1]]
        ] do
      %{pacing: pacing, effects: effects, room: room} = perform([count: count] ++ opts)
      sequence = room.reveal_sequence
      assert [{:timer, :hold, _, hold}] = effects
      assert hold == sequence.duration
      for step <- sequence.steps, do: assert(step.delay + step.duration <= hold)
      assert {:error, :reveal_held} = Pacing.may_advance(pacing, now(hold - 1))
      assert :ok = Pacing.may_advance(pacing, now(hold))
      assert Enum.count(sequence.steps, &(&1.role == :bridge_card)) == count
      assert Enum.count(sequence.steps, &(&1.role == :bridge_name)) == count

      assert Enum.count(sequence.steps, &(&1.role == :call_pin)) ==
               if(opts[:calls], do: count, else: 0)

      assert Enum.any?(sequence.steps, &(&1.role == :climb)) == !opts[:ungraded]
      assert Enum.any?(sequence.steps, &(&1.role == :meld_flash)) == (opts[:closeness] == 95)
      assert Enum.any?(sequence.steps, &(&1.role == :split_text)) == !!opts[:split]
      assert Enum.find(sequence.steps, &(&1.role == :rail)).delay <= 1_400
    end
  end

  test "the five-second hold absorbs the schedule without a second wait" do
    %{pacing: pacing, effects: effects} = perform(hold: 5_000, split: true, calls: true, count: 6)
    assert [{:timer, :hold, _, 5_000}] = effects
    assert :ok = Pacing.may_advance(pacing, now(5_000))
  end

  test "zero hold still stores the performance but never arms a hold timer" do
    %{pacing: pacing, effects: effects, room: room} = perform(hold: 0, split: true)
    assert effects == []
    assert room.reveal_sequence.duration == 1_840
    assert :ok = Pacing.may_advance(pacing, now(0))
  end

  test "missing and all-zero sequence settings produce an empty immediate performance" do
    for settings <- [nil, [], [stagger: 0, cap: 0, settle: 0]] do
      %{room: room, effects: effects} = perform(sequence: settings)
      assert %{duration: 0, elapsed: 0, steps: []} = room.reveal_sequence
      assert [{:timer, :hold, _, 1}] = effects
    end
  end

  test "a Seat watching this Page cannot stretch the schedule" do
    playing = perform(split: true, calls: true)
    watching = perform(split: true, calls: true, late: true)
    assert length(watching.room.seats) == 3
    assert watching.room.reveal_sequence == playing.room.reveal_sequence
  end

  test "snapshots, timer expiry and an Overrule preserve identity and deadline until leaving" do
    %{pacing: pacing, game: game, room: room, effects: [{:timer, :hold, token, deadline}]} =
      perform()

    original = room.reveal_sequence
    assert snapshot(pacing, game, -1).reveal_sequence.elapsed == 0
    assert snapshot(pacing, game, 500).reveal_sequence == %{original | elapsed: 500}

    ruled =
      game
      |> move({:overrule_proposed, %{seat_id: "Mara"}})
      |> move({:overrule_agreed, %{seat_id: "Bram"}})

    {pacing, []} = Pacing.moved(pacing, game, ruled, now(500))
    assert snapshot(pacing, ruled, 500).reveal_sequence == %{original | elapsed: 500}
    assert {:error, :reveal_held} = Pacing.may_advance(pacing, now(deadline - 1))
    {pacing, [:broadcast]} = Pacing.elapsed(pacing, :hold, token, now(deadline))
    assert snapshot(pacing, ruled, deadline).reveal_sequence.id == original.id
    assert {^pacing, []} = Pacing.elapsed(pacing, :hold, token, now(deadline + 1))
    turned = move(ruled, {:next_page, %{seat_id: "Mara"}})
    {pacing, []} = Pacing.moved(pacing, ruled, turned, now(deadline))
    assert snapshot(pacing, turned, deadline).reveal_sequence == nil
  end
end
