defmodule Thereish.Foley.CuesTest do
  @moduledoc """
  The Cues a screen plays between two of the Room's views. Every view here is
  one a Room produces: its play is driven command by command through
  `Play.apply/3`, and the asks a real Room would perform are answered by the
  command that answers them.
  """
  use ExUnit.Case, async: true

  alias Thereish.Foley.Cues
  alias Thereish.Rooms.Play
  alias Thereish.Rooms.Room

  @now %{ms: 0, at: ~U[2026-10-04 20:00:00Z]}
  @durations %{
    beat: 2_500,
    hold: 0,
    assayer: [slow: 4_000, unavailable: 10_000],
    author: [still_writing: 5_000, deadline: 20_000]
  }
  @members [
    %{name: "Dusk", title: "Dusk", path: "/loops/dusk.mp3"},
    %{name: "Dawn", title: "Dawn", path: "/loops/dawn.mp3"}
  ]
  @seats [%{id: "mara", name: "Mara"}, %{id: "jacob", name: "Jacob"}]
  # The device whose screen hears the Cues.
  @speaker "speaker-token"

  defp new do
    room = %Room{slug: "test", seat_limit: length(@seats)}
    Play.new(%{room: room, seats: @seats}, %{members: @members, durations: @durations, now: @now})
  end

  # Applies a command, answering the asks a real Room answers with a
  # follow-up command. Answers the Play and the effects of every step.
  defp run(play, command) do
    {:ok, play, effects} = Play.apply(play, command, @now)

    Enum.reduce(effects, {play, effects}, fn effect, {play, acc} ->
      case answer(effect) do
        nil ->
          {play, acc}

        command ->
          {play, more} = run(play, command)
          {play, acc ++ more}
      end
    end)
  end

  defp answer({:open_page, request, arm}), do: {:page_opened, request, arm || :flash, nil}
  defp answer({:look_up_track, page_ref, _gives}), do: {:track_looked_up, page_ref, nil}
  defp answer({:write_chronicle, _entry}), do: {:chronicle_written, Ecto.UUID.generate()}
  defp answer(_effect), do: nil

  defp find(effects, tag), do: Enum.find(effects, &(is_tuple(&1) and elem(&1, 0) == tag))

  defp view(play), do: Play.view(play, nil, @speaker, %{now: @now, has_chronicle?: false})

  defp claimed, do: claim(new())

  defp claim(play) do
    {play, _} = run(play, {:room_fact, {:claim_speaker, @speaker}})
    play
  end

  # Both Gives in. Answers the Play and the ask for the Author.
  defp given(play) do
    {play, _} = run(play, {:give, "mara", "deep canyon"})
    {play, opened} = run(play, {:give, "jacob", "echoing wind"})
    {play, opened}
  end

  # The Author's Bookends answered. Answers the Play at bridging and the Page
  # ref its Foley was asked under.
  defp written(play) do
    {play, opened} = given(play)
    {:ask_author, ref, _request, _arm} = find(opened, :ask_author)
    {:start_vamp, page_ref, _gives} = find(opened, :start_vamp)

    {play, _} =
      run(play, {:author_completed, ref, {:ok, %{bookends: ["lighthouse", "picnic"], meta: %{}}}})

    {play, page_ref}
  end

  defp commit(play, seat_id, bridge) do
    run(play, {:commit_bridge, seat_id, bridge})
  end

  # Both Bridges in. Answers the Play at the Beat and the Beat's timer token.
  defp bridged(play, a \\ "cairn", b \\ "cairn") do
    {play, _} = commit(play, "mara", a)
    {play, effects} = commit(play, "jacob", b)
    {:timer, :beat, token, _ms} = find(effects, :timer)
    {play, token}
  end

  # The Assayer's event lands during the Beat and is applied when it ends.
  defp assayed(play, token, event) do
    {play, _} = run(play, {:assayed, event})
    {play, _} = run(play, {:pacing, :beat, token})
    play
  end

  defp verdict(closeness) do
    {:verdict_received,
     %{closeness: closeness, reasoning: "r", quip: "q", furthest: ["cairn", "cairo"], meta: %{}}}
  end

  defp page(view) do
    %{path: path, title: title, kind: kind} = view.playing
    {:page, path, title, kind}
  end

  describe "a screen's first render" do
    test "the Speaker hears the Page's music" do
      new = view(claimed())

      assert Cues.between(nil, new, :phone) == [page(new)]
      assert Cues.between(nil, new, :stage) == [page(new)]
    end

    test "a screen without the Speaker hears nothing" do
      assert Cues.between(nil, view(new()), :phone) == []
      assert Cues.between(nil, view(new()), :stage) == []
    end

    test "a Prologue already playing starts with the music" do
      {play, _} = run(claimed(), {:room_fact, :play_prologue})
      new = view(play)

      assert Cues.between(nil, new, :stage) == [page(new), {:prologue, new.prologue.reading}]
    end

    test "a Stage arriving mid-Page hears no commit tick" do
      {play, _} = written(claimed())
      {play, _} = commit(play, "mara", "cairn")
      new = view(play)

      assert Cues.between(nil, new, :stage) == [page(new)]
    end
  end

  describe "the Page's music" do
    test "is not cued again when the Gives are in" do
      play = claimed()
      {written, _} = given(play)

      assert view(written).phase == :writing
      assert Cues.between(view(play), view(written), :phone) == []
    end

    test "is cued again when the Author's Bookends open bridging" do
      {play, _} = given(claimed())
      {bridging, _} = written(claimed())
      new = view(bridging)

      assert new.phase == :bridging
      assert Cues.between(view(play), new, :phone) == [page(new)]
    end

    test "is cued when the Vamp lands, and again when the Track lands" do
      {play, page_ref} = written(claimed())
      {vamped, _} = run(play, {:vamped, page_ref, {:ok, %{path: "/media/vamp.mp3"}}})

      assert Cues.between(view(play), view(vamped), :phone) ==
               [{:page, "/media/vamp.mp3", nil, "vamp"}]

      {scored, _} =
        run(vamped, {:scored, page_ref, {:ok, %{path: "/media/track.mp3", meta: %{}}}})

      assert [{:page, "/media/track.mp3", _title, "track"}] =
               Cues.between(view(vamped), view(scored), :phone)
    end

    test "a held-over Track is not cued again when the next Page's Gives are in" do
      {play, page_ref} = written(claimed())
      {play, _} = run(play, {:scored, page_ref, {:ok, %{path: "/media/track.mp3", meta: %{}}}})
      {play, token} = bridged(play)
      closed = assayed(play, token, verdict(95))
      {turned, _} = run(closed, {:next_page, "mara", @members})
      {writing, _} = given(turned)

      assert %{path: "/media/track.mp3", kind: "holdover"} = view(writing).playing
      assert Cues.between(view(turned), view(writing), :phone) == []
    end

    test "is cued with no path when the music is switched off" do
      play = claimed()
      {off, _} = run(play, {:room_fact, {:set_music, "off"}})

      assert Cues.between(view(play), view(off), :phone) == [{:page, nil, nil, nil}]
    end
  end

  describe "the Stage's commit tick" do
    test "plays on the Stage, not a phone, when a Seat commits" do
      {play, _} = written(claimed())
      {committed, _} = commit(play, "mara", "cairn")

      assert Cues.between(view(play), view(committed), :stage) == [:commit]
      assert Cues.between(view(play), view(committed), :phone) == []
    end

    test "plays on a Stage that does not hold the Speaker" do
      {play, _} = written(new())
      {committed, _} = commit(play, "mara", "cairn")

      assert Cues.between(view(play), view(committed), :stage) == [:commit]
    end

    test "plays before the Beat when the last Seat commits" do
      {play, _} = written(claimed())
      {play, _} = commit(play, "mara", "cairn")
      {assaying, _} = commit(play, "jacob", "cairn")

      assert view(assaying).phase == :assaying
      assert Cues.between(view(play), view(assaying), :stage) == [:commit, :beat]
      assert Cues.between(view(play), view(assaying), :phone) == [:beat]
    end

    test "does not play when nothing was committed" do
      {play, _} = written(claimed())

      assert Cues.between(view(play), view(play), :stage) == []
    end

    test "does not play across Attempts" do
      {play, _} = written(claimed())
      {play, token} = bridged(play, "cairn", "cairo")
      revealed = assayed(play, token, verdict(10))
      {next, _} = run(revealed, {:next_attempt, "mara"})
      {committed, _} = commit(next, "mara", "harbour")

      refute :commit in Cues.between(view(revealed), view(committed), :stage)
    end

    test "plays before the stop when the Stage loses the Speaker" do
      {play, _} = written(claimed())
      {committed, _} = commit(play, "jacob", "cairn")
      {lost, _} = run(committed, {:room_fact, {:claim_speaker, "phone-token"}})

      assert Cues.between(view(play), view(lost), :stage) == [:commit, :stop]
    end
  end

  describe "the reveal" do
    test "a miss stings with its band" do
      {play, _} = written(claimed())
      {play, token} = bridged(play, "cairn", "cairo")
      revealed = assayed(play, token, verdict(10))

      assert view(revealed).phase == :reveal
      assert Cues.between(view(play), view(revealed), :phone) == [{:sting, :miss}]
    end

    test "a Verdict with no band stings as a miss" do
      {play, _} = written(claimed())
      {play, token} = bridged(play, "cairn", "cairo")
      revealed = assayed(play, token, {:verdict_unavailable, %{meta: %{}}})

      assert view(revealed).reveal.band == nil
      assert Cues.between(view(play), view(revealed), :phone) == [{:sting, :miss}]
    end

    test "the next Attempt stops the last Attempt's Voice clip" do
      {play, _} = written(claimed())
      {play, token} = bridged(play, "cairn", "cairo")
      revealed = assayed(play, token, verdict(10))
      {next, _} = run(revealed, {:next_attempt, "mara"})

      assert Cues.between(view(revealed), view(next), :phone) == [{:stop_voice, 2}]
    end
  end

  describe "the ending" do
    test "a meld stings and ends as a meld" do
      {play, _} = written(claimed())
      {play, token} = bridged(play)
      closed = assayed(play, token, verdict(95))

      assert Cues.between(view(play), view(closed), :phone) == [
               {:sting, :meld},
               {:ending, :meld}
             ]
    end

    test "a deep meld ends as a deep meld" do
      {play, _} = written(claimed())
      {play, token} = bridged(play)
      closed = assayed(play, token, verdict(100))

      assert Cues.between(view(play), view(closed), :phone) == [
               {:sting, :deep_meld},
               {:ending, :deep_meld}
             ]
    end

    test "spending every Attempt ends unmelded" do
      {play, _} = written(claimed())
      {last, closed} = spend_attempts(play)

      assert view(closed).phase == :closed

      assert Cues.between(view(last), view(closed), :phone) == [
               {:sting, :miss},
               {:ending, :unmelded}
             ]
    end

    test "a closed Page ends once" do
      {play, _} = written(claimed())
      {play, token} = bridged(play)
      closed = assayed(play, token, verdict(95))
      {tapped, _} = run(closed, {:tap_bookends, "mara", "great"})

      assert Cues.between(view(closed), view(tapped), :phone) == []
    end

    test "is not heard without the Speaker" do
      {play, _} = written(new())
      {play, token} = bridged(play)
      closed = assayed(play, token, verdict(95))

      assert Cues.between(view(play), view(closed), :phone) == []
    end
  end

  # Misses every Attempt. Answers the Play at the last Beat and the closed Play.
  defp spend_attempts(play) do
    attempts = Thereish.Game.attempt_cap()

    Enum.reduce(1..attempts, {play, nil}, fn n, {play, _} ->
      {play, token} = bridged(play, "cairn#{n}", "cairo#{n}")
      done = assayed(play, token, verdict(10))

      if n == attempts do
        {play, done}
      else
        {next, _} = run(done, {:next_attempt, "mara"})
        {next, nil}
      end
    end)
  end

  describe "the Speaker" do
    test "a device that loses it only stops all sound" do
      {play, _} = written(claimed())
      {play, token} = bridged(play)
      {lost, _} = run(play, {:room_fact, {:claim_speaker, "phone-token"}})
      closed = assayed(lost, token, verdict(95))

      assert Cues.between(view(play), view(closed), :phone) == [:stop]
    end

    test "a device that claims it hears the Page's music" do
      play = new()
      new = view(claim(play))

      assert Cues.between(view(play), new, :phone) == [page(new)]
    end

    test "a device that claims it mid-Prologue hears the Prologue" do
      {play, _} = run(new(), {:room_fact, :play_prologue})
      new = view(claim(play))

      assert Cues.between(view(play), new, :stage) == [
               page(new),
               {:prologue, new.prologue.reading}
             ]
    end
  end

  describe "the Prologue" do
    test "playing it starts it" do
      play = claimed()
      {played, _} = run(play, {:room_fact, :play_prologue})

      assert Cues.between(view(play), view(played), :stage) ==
               [{:prologue, view(played).prologue.reading}]
    end

    test "skipping it stops it" do
      {play, _} = run(claimed(), {:room_fact, :play_prologue})
      {skipped, _} = run(play, {:room_fact, :skip_prologue})

      assert Cues.between(view(play), view(skipped), :stage) == [:stop_prologue]
    end
  end
end
