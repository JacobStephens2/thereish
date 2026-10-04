defmodule Thereish.Rooms.PlayTest do
  @moduledoc """
  The Room's play, driven command by command through `Play.apply/3` and
  asserted on the effects it answers and on the view, never on the six
  modules inside it. No process, no database and no waits: each ask a real
  Room would perform is answered here by the command that answers it.
  """
  use ExUnit.Case, async: true

  alias Thereish.Mask
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
  @seats [%{id: "melissa", name: "Melissa"}, %{id: "jacob", name: "Jacob"}]
  @speaker "speaker-token"
  @track %{path: "/media/track.mp3", meta: %{provider: "fake"}}

  # A Room as full as its Seats, unless `room` says otherwise.
  defp new(opts \\ []) do
    seats = Keyword.get(opts, :seats, @seats)
    room = struct!(%Room{slug: "test", seat_limit: length(seats)}, Keyword.get(opts, :room, %{}))
    durations = Keyword.get(opts, :durations, @durations)
    Play.new(%{room: room, seats: seats}, %{members: @members, durations: durations, now: @now})
  end

  # Applies a command the Room's process would run, answering the asks that
  # a real Room answers with a follow-up command. `writes` names the Chronicle
  # Page id each `{:write_chronicle, _}` comes back with.
  defp run(play, command, opts \\ []) do
    {:ok, play, effects} = Play.apply(play, command, @now)
    follow_up(play, effects, opts)
  end

  defp follow_up(play, effects, opts) do
    Enum.reduce(effects, {play, []}, fn effect, {play, acc} ->
      case answer(effect, opts) do
        nil ->
          {play, acc ++ [effect]}

        command ->
          {play, more} = run(play, command, opts)
          {play, acc ++ [effect | more]}
      end
    end)
  end

  defp answer({:open_page, request, arm}, _opts), do: {:page_opened, request, arm || :flash, nil}
  defp answer({:look_up_track, page_ref, _gives}, _opts), do: {:track_looked_up, page_ref, nil}

  defp answer({:write_chronicle, _entry}, opts),
    do: opts[:written] && {:chronicle_written, opts[:written]}

  defp answer(_effect, _opts), do: nil

  defp find(effects, tag), do: Enum.find(effects, &(is_tuple(&1) and elem(&1, 0) == tag))
  defp tags(effects), do: Enum.map(effects, &if(is_tuple(&1), do: elem(&1, 0), else: &1))

  defp view(play, viewer \\ nil, token \\ nil, chronicle? \\ false),
    do: Play.view(play, viewer, token, %{now: @now, has_chronicle?: chronicle?})

  defp phase(play), do: view(play).phase

  # Both Gives in, the Author asked and answered. Answers the Play at the
  # Bookends, the Page ref its Foley was asked under and the giving ref its
  # Masks were drawn under.
  defp written(play) do
    {play, given} = run(play, {:give, "melissa", "deep canyon"})
    {play, opened} = run(play, {:give, "jacob", "echoing wind"})
    {:draw_mask, "melissa", giving, "deep canyon", _colour} = find(given, :draw_mask)
    {:ask_author, ref, _request, _arm} = find(opened, :ask_author)
    {:start_vamp, page_ref, _gives} = find(opened, :start_vamp)

    {play, _} =
      run(play, {:author_completed, ref, {:ok, %{bookends: ["lighthouse", "picnic"], meta: %{}}}})

    {play, page_ref, giving}
  end

  defp bridges(play, a, b, opts \\ []) do
    {play, _} = run(play, {:commit_bridge, "melissa", a}, opts)
    run(play, {:commit_bridge, "jacob", b}, opts)
  end

  defp verdict(closeness, quip \\ "a quip") do
    {:verdict_received,
     %{closeness: closeness, reasoning: "r", quip: quip, furthest: ["cairn", "cairo"], meta: %{}}}
  end

  # The Verdict lands during the Beat and is applied when the Beat ends.
  defp assayed(play, bridged, closeness, opts) do
    {:timer, :beat, token, _ms} = find(bridged, :timer)
    {play, heard} = run(play, {:assayed, verdict(closeness)}, opts)
    {play, beat} = run(play, {:pacing, :beat, token}, opts)
    {play, heard ++ beat}
  end

  # Plays a written Page to a meld.
  defp meld(play, opts \\ []) do
    {play, bridged} = bridges(play, "cairn", "cairn", opts)
    assayed(play, bridged, 95, opts)
  end

  describe "joining" do
    test "a Seat the rules take is inserted before anything else is performed" do
      play = new(seats: [], room: %{seat_limit: 2})

      assert {:ok, play, [{:insert_seat, "melissa", "Melissa"} | rest]} =
               Play.apply(play, {:seat_joined, "melissa", "Melissa"}, @now)

      assert :broadcast in rest
      assert [%{id: "melissa", name: "Melissa"}] = view(play).seats
    end

    test "a full Room refuses the Seat and asks for no insert" do
      assert Play.apply(new(), {:seat_joined, "ada", "Ada"}, @now) == {:error, :room_full}
    end
  end

  describe "Room facts" do
    test "a changed fact is written first, then broadcast, then its effects are performed" do
      {play, _page_ref, _giving} = written(new())

      assert {:ok, play, [{:persist_room, %{speaker: @speaker}}, :broadcast | voiced]} =
               Play.apply(play, {:room_fact, {:claim_speaker, @speaker}}, @now)

      assert {:speak, 1, :bookends, _line} = find(voiced, :speak)
      assert view(play, nil, @speaker).speaker?
    end

    test "a fact that changes nothing writes nothing and is not broadcast" do
      {play, _} = run(new(), {:room_fact, {:claim_speaker, @speaker}})

      assert {:ok, ^play, []} = Play.apply(play, {:room_fact, {:claim_speaker, @speaker}}, @now)
    end

    test "a fact that is not persisted is broadcast with no write" do
      assert {:ok, play, [:broadcast]} = Play.apply(new(), {:room_fact, :play_prologue}, @now)
      assert %{reading: _, text: _} = view(play).prologue
    end

    test "skipping the Prologue ends the take playing and is written" do
      {play, _} = run(new(), {:room_fact, :play_prologue})

      assert {:ok, play, [{:persist_room, %{prologue_skipped: true}}, :broadcast]} =
               Play.apply(play, {:room_fact, :skip_prologue}, @now)

      assert view(play).prologue == nil
      assert view(play).prologue_skipped
    end

    test "a music setting the Room does not have is refused" do
      assert Play.apply(new(), {:room_fact, {:set_music, "loud"}}, @now) ==
               {:error, :bad_music_setting}
    end

    test "the music setting reaches what the Room plays" do
      assert view(new()).playing.kind == "repertoire"

      {play, effects} = run(new(), {:room_fact, {:set_music, "off"}})
      assert [{:persist_room, %{music: "off"}}, :broadcast] = effects
      assert view(play).playing == nil
      assert view(play).music == "off"
    end

    test "Full table reaches the Game: the next Page opens on two Bookends" do
      seats = @seats ++ [%{id: "ada", name: "Ada"}]
      play = new(seats: seats)

      {play, effects} = run(play, {:room_fact, {:set, :full_table, false}})
      assert [{:persist_room, %{full_table: false}}, :broadcast] = effects

      {play, _} = run(play, {:give, "melissa", "deep canyon"})
      {play, _} = run(play, {:give, "jacob", "echoing wind"})
      {_play, opened} = run(play, {:give, "ada", "quiet harbour"})

      assert {:open_page, %{count: 2}, nil} = find(opened, :open_page)
    end

    test "flipping Full table mid-Page leaves that Page's Bookends" do
      {play, _page_ref, _giving} = written(new())
      bookends = view(play).bookends

      {play, _} = run(play, {:room_fact, {:set, :full_table, false}})

      assert view(play).full_table == false
      assert view(play).phase == :bridging
      assert view(play).bookends == bookends
    end
  end

  describe "the Speaker's Next and Never" do
    setup do
      {play, _} = run(new(), {:room_fact, {:claim_speaker, @speaker}})
      %{play: play}
    end

    test "are ignored from a device that does not hold the Speaker", %{play: play} do
      for press <- [:next, :never], token <- ["another-token", nil] do
        assert {:ok, ^play, []} = Play.apply(play, {press, token}, @now)
      end
    end

    test "Next draws another member and is broadcast", %{play: play} do
      playing = view(play, nil, @speaker).playing

      assert {:ok, play, effects} = Play.apply(play, {:next, @speaker}, @now)
      assert List.last(effects) == :broadcast
      refute view(play, nil, @speaker).playing.path == playing.path
    end

    test "Never records the member and is broadcast", %{play: play} do
      %{path: path} = view(play, nil, @speaker).playing

      assert {:ok, play, effects} = Play.apply(play, {:never, @speaker}, @now)
      assert {:record_never, ^path} = find(effects, :record_never)
      assert List.last(effects) == :broadcast
      refute view(play, nil, @speaker).playing.path == path
    end
  end

  describe "the view" do
    test "merges the Game's view, Pacing's waits, the Room facts and what is playing" do
      {play, _page_ref, _giving} = written(new(room: %{quips: false}))

      view = view(play, "melissa", "a-token", true)

      assert view.phase == :bridging
      assert view.bookends == ["lighthouse", "picnic"]
      assert %{author_step: nil, assayer_step: nil, can_advance?: false} = view
      assert view.quips == false
      assert view.speaker? == false
      assert view.playing.kind == "repertoire"
      assert view.has_chronicle? == true
    end

    test "answers whether this device holds the Speaker, and never a device token" do
      {play, _} = run(new(), {:room_fact, {:claim_speaker, @speaker}})

      assert view(play, "melissa", @speaker).speaker?
      refute view(play, "jacob", "another-token").speaker?
      assert view(play, nil, nil).speaker_claimed?

      for token <- [@speaker, "another-token", nil] do
        view = view(play, nil, token)

        for key <- [:speaker, :device_token, :voice, :house_loop_only],
            do: refute(Map.has_key?(view, key))

        refute Jason.encode!(view) =~ @speaker
      end
    end
  end

  describe "a whole Page" do
    test "Gives, the Author's answer, Bridges, the Beat, the Verdict, the close and its write" do
      play = new()
      assert phase(play) == :giving

      {play, given} = run(play, {:give, "melissa", "deep canyon"})
      assert :broadcast in given
      assert {:draw_mask, "melissa", _giving, "deep canyon", _colour} = find(given, :draw_mask)

      {play, opened} = run(play, {:give, "jacob", "echoing wind"})
      assert {:open_page, %{gives: [_, _]} = request, nil} = find(opened, :open_page)
      assert {:ask_author, ref, ^request, :flash} = find(opened, :ask_author)
      assert phase(play) == :writing

      {play, answered} =
        run(
          play,
          {:author_completed, ref, {:ok, %{bookends: ["lighthouse", "picnic"], meta: %{}}}}
        )

      assert :broadcast in answered
      assert view(play).bookends == ["lighthouse", "picnic"]

      {play, bridged} = bridges(play, "cairn", "cairn")
      assert {:ask_assayer, %{bridges: _}, []} = find(bridged, :ask_assayer)
      assert phase(play) == :assaying

      # The Verdict is held for the Beat, then applied.
      {:timer, :beat, token, 2_500} = find(bridged, :timer)
      {play, heard} = run(play, {:assayed, verdict(95)})
      assert find(heard, :write_chronicle) == nil
      assert phase(play) == :assaying

      {play, closed} = run(play, {:pacing, :beat, token}, written: "page-1")
      assert phase(play) == :closed

      assert {:write_chronicle, entry} = find(closed, :write_chronicle)
      assert entry.arm == :flash
      assert entry.opened_at == @now.at
      assert entry.melded?

      # A Track landing after the close goes onto the written Page.
      {:start_vamp, page_ref, _gives} = find(opened, :start_vamp)
      {_play, late} = run(play, {:scored, page_ref, {:ok, @track}})
      assert {:write_page, "page-1", {:music, _meta}} = find(late, :write_page)
    end

    test "a refused command answers the Game's reason" do
      assert Play.apply(new(), {:commit_bridge, "melissa", "cairn"}, @now) ==
               {:error, :not_bridging}
    end

    test "a superseded Author's answer changes nothing" do
      {play, _} = run(new(), {:give, "melissa", "deep canyon"})
      {play, _} = run(play, {:give, "jacob", "echoing wind"})

      assert {:ok, ^play, []} =
               Play.apply(
                 play,
                 {:author_completed, make_ref(), {:ok, %{bookends: ["a", "b"]}}},
                 @now
               )
    end
  end

  describe "a turned Page" do
    test "a Page whose write Voice held is still written, with what was held for it" do
      {play, _} = run(new(), {:room_fact, {:claim_speaker, @speaker}})
      {play, _page_ref, giving} = written(play)

      # With a Speaker, the Verdict is spoken, so the close waits for it.
      {play, closed} = meld(play)
      assert {:speak, 1, :verdict, _line} = find(closed, :speak)
      assert find(closed, :write_chronicle) == nil

      {play, tapped} = run(play, {:tap_bookends, "melissa", "great"})
      assert find(tapped, :write_page) == nil

      {play, turned} = run(play, {:next_page, "melissa", @members}, written: "page-1")

      # The held write lands first, and the tap it releases, before the turn
      # is broadcast.
      assert [:write_chronicle, :write_page | _] = tags(turned)

      assert {:write_page, "page-1", {:bookends_tap, %{label: "great"}}} =
               find(turned, :write_page)

      assert phase(play) == :giving

      # The turned Page's Gives still name it; the new Gives do not.
      {play, landed} =
        run(play, {:mask_landed, "melissa", giving, %Mask{url: "/m.png", meta: %{}}})

      assert {:write_page, "page-1", {:mask, "melissa", _mask}} = find(landed, :write_page)

      {_play, given} = run(play, {:give, "melissa", "harbour"})
      assert {:draw_mask, "melissa", new_giving, _give, _colour} = find(given, :draw_mask)
      refute new_giving == giving
    end
  end

  describe "results that land while Voice holds the write" do
    test "a Bookends tap and a Track are written onto that Page, in the order they landed" do
      {play, _} = run(new(), {:room_fact, {:claim_speaker, @speaker}})
      {play, page_ref, _giving} = written(play)
      {play, closed} = meld(play)
      {:speak, 1, :verdict, _line} = find(closed, :speak)

      {play, tapped} = run(play, {:tap_bookends, "jacob", "flat"})
      {play, scored} = run(play, {:scored, page_ref, {:ok, @track}})
      assert find(tapped ++ scored, :write_page) == nil

      {_play, spoken} =
        run(play, {:voice_spoken, 1, :verdict, {:ok, %{audio: "mp3", meta: %{}}}},
          written: "page-1"
        )

      assert [
               {:write_chronicle, entry},
               {:write_page, "page-1", {:bookends_tap, %{label: "flat"}}},
               {:write_page, "page-1", {:music, %{path: "/media/track.mp3"}}},
               {:broadcast, {:voice_ready, 1}}
             ] = spoken

      assert [%{verdicts: [%{voice_meta: %{"provider" => _}}]}] = entry.attempts
    end

    test "a write that failed releases nothing: the results held for it stay held" do
      {play, _} = run(new(), {:room_fact, {:claim_speaker, @speaker}})
      {play, _page_ref, _giving} = written(play)
      {play, _} = meld(play)
      {play, _} = run(play, {:tap_bookends, "jacob", "flat"})

      {_play, spoken} = run(play, {:voice_spoken, 1, :verdict, {:error, %{"failure" => "x"}}})
      assert {:write_chronicle, _entry} = find(spoken, :write_chronicle)
      assert find(spoken, :write_page) == nil
    end
  end

  describe "a reset of Gives" do
    test "after the Author has answered, it is refused and leaves that Page's music alone" do
      {play, page_ref, _giving} = written(new())

      assert {:error, :not_writing} = Play.apply(play, {:reset_gives, "melissa"}, @now)

      {play, vamped} = run(play, {:vamped, page_ref, {:ok, %{path: "/media/vamp.mp3"}}})
      assert :broadcast in vamped
      assert view(play).vamp.path == "/media/vamp.mp3"
    end

    test "after the Author has answered, it leaves that Page's times alone" do
      {play, _page_ref, _giving} = written(new())
      later = %{ms: 60_000, at: DateTime.add(@now.at, 60)}

      assert {:error, :not_writing} = Play.apply(play, {:reset_gives, "jacob"}, later)

      {_play, closed} = meld(play, written: "page-1")
      {:write_chronicle, entry} = find(closed, :write_chronicle)
      assert entry.opened_at == @now.at
      assert length(entry.gives) == 2
      assert Enum.all?(entry.gives, &(&1.arrived_at == @now.at))
    end

    test "before the Author answers, its answer and its Foley are dropped" do
      {play, _} = run(new(), {:give, "melissa", "deep canyon"})
      {play, opened} = run(play, {:give, "jacob", "echoing wind"})
      {:ask_author, ref, _request, :flash} = find(opened, :ask_author)
      {:start_vamp, page_ref, _gives} = find(opened, :start_vamp)

      {play, reset} = run(play, {:reset_gives, "melissa"})
      assert :broadcast in reset
      assert phase(play) == :giving

      bookends = %{bookends: ["lighthouse", "picnic"], meta: %{}}
      assert {:ok, ^play, []} = Play.apply(play, {:author_completed, ref, {:ok, bookends}}, @now)

      {play, vamped} = run(play, {:vamped, page_ref, {:ok, %{path: "/media/vamp.mp3"}}})
      assert vamped == []
      assert view(play).vamp == nil
    end

    test "new Gives keep the Page's arm, so the Room is asked for none" do
      {play, _} = run(new(), {:give, "melissa", "deep canyon"})
      {play, _} = run(play, {:give, "jacob", "echoing wind"})
      {play, _} = run(play, {:reset_gives, "melissa"})
      {play, _} = run(play, {:give, "melissa", "harbour"})
      {_play, opened} = run(play, {:give, "jacob", "lantern"})

      assert {:open_page, _request, :flash} = find(opened, :open_page)
    end
  end

  describe "a Mask for the Gives in play" do
    test "is the Game's, so a late drawn Mask replaces the dot and every screen hears it" do
      {play, given} = run(new(), {:give, "melissa", "candlelit cathedral"})
      {:draw_mask, "melissa", giving, _give, _colour} = find(given, :draw_mask)

      {play, _} = run(play, {:mask_landed, "melissa", giving, :dot})
      assert view(play, "melissa").your_mask == :dot

      mask = %Mask{url: "/media/masks/late.png", meta: %{}}
      {play, landed} = run(play, {:mask_landed, "melissa", giving, mask})

      assert :broadcast in landed
      assert view(play, "melissa").your_mask == mask
      assert Enum.find(view(play, "melissa").seats, &(&1.id == "melissa")).mask == mask
    end
  end

  describe "a Mask for Gives already past" do
    setup do
      {play, _page_ref, giving} = written(new())
      {play, _} = meld(play, written: "page-1")
      {play, _} = run(play, {:next_page, "melissa", @members})
      %{play: play, giving: giving}
    end

    test "is written onto its Page when it was drawn", %{play: play, giving: giving} do
      mask = %Mask{url: "/media/masks/late.png", meta: %{}}

      assert {play, [{:write_page, "page-1", {:mask, "jacob", ^mask}}, :broadcast]} =
               run(play, {:mask_landed, "jacob", giving, mask})

      assert view(play, "jacob").your_mask == nil
    end

    test "is dropped when it is the dot", %{play: play, giving: giving} do
      assert {:ok, ^play, []} = Play.apply(play, {:mask_landed, "jacob", giving, :dot}, @now)
    end
  end

  describe "the Assayer's prior Quips" do
    test "the in-play half is this Page's graded Quips, oldest first" do
      {play, _page_ref, _giving} = written(new())
      {play, bridged} = bridges(play, "cairn", "cairo")
      {:ask_assayer, _request, []} = find(bridged, :ask_assayer)

      {:timer, :beat, token, _ms} = find(bridged, :timer)
      {play, _} = run(play, {:assayed, verdict(10, "a first quip")})
      {play, _} = run(play, {:pacing, :beat, token})
      assert phase(play) == :reveal

      {play, _} = run(play, {:next_attempt, "melissa"})
      {_play, bridged} = bridges(play, "harbour", "lantern")

      assert {:ask_assayer, _request, ["a first quip"]} = find(bridged, :ask_assayer)
    end
  end

  describe "the reveal hold" do
    test "holds Next Attempt and Next Page alike until it is over" do
      play = new(durations: %{@durations | hold: 5_000})

      {play, _page_ref, _giving} = written(play)
      {play, bridged} = bridges(play, "cairn", "cairo")
      {:timer, :beat, token, _ms} = find(bridged, :timer)
      {play, _} = run(play, {:assayed, verdict(10)})
      {play, revealed} = run(play, {:pacing, :beat, token})
      assert {:timer, :hold, _token, 5_000} = find(revealed, :timer)

      assert {:error, :reveal_held} = Play.apply(play, {:next_attempt, "melissa"}, @now)
      assert {:error, :reveal_held} = Play.apply(play, {:next_page, "melissa", @members}, @now)

      assert {:ok, _play, _effects} =
               Play.apply(play, {:next_attempt, "melissa"}, %{@now | ms: 5_000})
    end
  end
end
