defmodule MeaningGame.GameTest do
  @moduledoc """
  The rules, driven as a list of events and asserted on the projected view.

  Everything here goes through `init`, `apply` and `view`, because that is all a
  Room has to work with and all a later Page will have either. Where a test
  needs a pair of Seats to grade, it takes the pair out of the effects the rules
  emitted rather than assembling one itself — the Room has nothing else either.
  """
  use ExUnit.Case, async: true

  alias MeaningGame.Game

  @page %{id: "test-page", anchors: ["lantern", "harbour"]}

  defp seat(name), do: %{id: "seat-" <> name, name: name}

  defp names(view), do: Enum.map(view.seats, & &1.name)

  defp play(state, events) do
    Enum.reduce(events, state, fn event, state ->
      {:ok, state, _effects} = Game.apply(state, event)
      state
    end)
  end

  # A Room that is full and holding a Page: the state every Page test starts in.
  defp bridging(names \\ ["Mara", "Jacob"]) do
    Game.init(seat_limit: length(names), seats: Enum.map(names, &seat/1), page: @page)
  end

  defp commit(state, name, bridge) do
    Game.apply(state, {:bridge_committed, %{seat_id: "seat-" <> name, bridge: bridge}})
  end

  # Commits every Bridge in order and hands back the effects of the last commit,
  # which is the only one that has any.
  defp commit_all(state, bridges) do
    Enum.reduce(bridges, {state, []}, fn {name, bridge}, {state, _effects} ->
      {:ok, state, effects} = commit(state, name, bridge)
      {state, effects}
    end)
  end

  defp assays(effects), do: Enum.filter(effects, &match?({:assay, _pair, _request}, &1))

  # Grades the pairs in the order they were asked for.
  defp grade(state, effects, closenesses) do
    effects
    |> assays()
    |> Enum.zip(closenesses)
    |> Enum.reduce(state, fn {{:assay, pair, _request}, closeness}, state ->
      event = {:verdict_received, %{pair: pair, closeness: closeness, reasoning: "because"}}
      {:ok, state, []} = Game.apply(state, event)
      state
    end)
  end

  # The whole Page in one line, for tests that are about the reveal rather than
  # the road to it.
  defp revealed(bridges, closenesses) do
    {state, effects} = commit_all(bridging(), bridges)
    grade(state, effects, closenesses)
  end

  # Three Seats with every Bridge in: the Page that has three pairs to grade.
  defp three_committed do
    commit_all(bridging(["Mara", "Jacob", "Ada"]), [
      {"Mara", "cairn"},
      {"Jacob", "beacon"},
      {"Ada", "harbourmaster"}
    ])
  end

  describe "seats are a list of N" do
    test "a Room of three seats takes a third player the same way it took the first two" do
      state =
        Game.init(seat_limit: 3)
        |> play([
          {:seat_joined, seat("Mara")},
          {:seat_joined, seat("Jacob")},
          {:seat_joined, seat("Ada")}
        ])

      assert names(Game.view(state, nil)) == ["Mara", "Jacob", "Ada"]
      assert Game.view(state, nil).open_seats == 0
    end

    test "a Room turns away a player once its seats are gone" do
      state =
        Game.init(seat_limit: 2)
        |> play([{:seat_joined, seat("Mara")}, {:seat_joined, seat("Jacob")}])

      assert {:error, :room_full} = Game.apply(state, {:seat_joined, seat("Ada")})
    end

    test "existing seats are restored without being replayed" do
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])

      assert names(Game.view(state, nil)) == ["Mara", "Jacob"]
      assert Game.view(state, nil).open_seats == 0
    end
  end

  describe "rejoining" do
    test "a seat already in the Room joining again changes nothing" do
      state = play(Game.init(seat_limit: 2), [{:seat_joined, seat("Mara")}])

      assert {:ok, ^state, []} = Game.apply(state, {:seat_joined, seat("Mara")})
    end

    test "a full Room still takes a rejoin from a seat it already holds" do
      state = Game.init(seat_limit: 1, seats: [seat("Mara")])

      assert {:ok, ^state, []} = Game.apply(state, {:seat_joined, seat("Mara")})
    end
  end

  describe "view" do
    setup do
      %{state: Game.init(seat_limit: 3, seats: [seat("Mara"), seat("Jacob")])}
    end

    test "every viewer sees the same roster in the same order", %{state: state} do
      assert names(Game.view(state, "seat-Mara")) == ["Mara", "Jacob"]
      assert names(Game.view(state, "seat-Jacob")) == ["Mara", "Jacob"]
      assert names(Game.view(state, nil)) == ["Mara", "Jacob"]
    end

    test "each seat is told which one is its own", %{state: state} do
      view = Game.view(state, "seat-Mara")

      assert view.you.name == "Mara"
      assert view.seats |> Enum.filter(& &1.you?) |> Enum.map(& &1.name) == ["Mara"]
    end

    test "a viewer holding no seat is nobody in the roster", %{state: state} do
      view = Game.view(state, nil)

      assert view.you == nil
      refute Enum.any?(view.seats, & &1.you?)
    end

    test "the view counts the seats still open", %{state: state} do
      view = Game.view(state, "seat-Mara")

      assert view.seat_limit == 3
      assert view.open_seats == 1
    end
  end

  describe "before the Page starts" do
    test "a Room still short a player is waiting rather than bridging" do
      state = Game.init(seat_limit: 2, seats: [seat("Mara")], page: @page)

      assert Game.view(state, "seat-Mara").phase == :waiting
      assert {:error, :not_bridging} = commit(state, "Mara", "cairn")
    end

    test "the player who got there first does not get the Anchors first" do
      state = Game.init(seat_limit: 2, seats: [seat("Mara")], page: @page)

      assert Game.view(state, "seat-Mara").anchors == nil
      refute inspect(Game.view(state, "seat-Mara")) =~ "lantern"
    end

    test "a Room with no Page is waiting however full it is" do
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])

      assert Game.view(state, nil).phase == :waiting
      assert Game.view(state, nil).anchors == nil
    end

    test "the last player to join starts the Page for everyone" do
      state =
        Game.init(seat_limit: 2, seats: [seat("Mara")], page: @page)
        |> play([{:seat_joined, seat("Jacob")}])

      for viewer <- ["seat-Mara", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :bridging
        assert view.anchors == ["lantern", "harbour"]
      end
    end
  end

  describe "writing a Bridge" do
    test "a Seat's own Bridge is its own to see" do
      {:ok, state, []} = commit(bridging(), "Mara", "cairn")

      assert Game.view(state, "seat-Mara").your_bridge == "cairn"
    end

    test "an uncommitted Bridge is invisible to every other Seat" do
      {:ok, state, []} = commit(bridging(), "Mara", "cairn")

      assert Game.view(state, "seat-Jacob").your_bridge == nil
      assert Game.view(state, nil).your_bridge == nil

      # Not merely absent from the field it would be read out of: nowhere in
      # what the other phone or the stage is handed.
      refute inspect(Game.view(state, "seat-Jacob")) =~ "cairn"
      refute inspect(Game.view(state, nil)) =~ "cairn"
    end

    test "every Seat sees that another has committed without seeing what it wrote" do
      {:ok, state, []} = commit(bridging(), "Mara", "cairn")

      for viewer <- ["seat-Mara", "seat-Jacob", nil] do
        committed = for seat <- Game.view(state, viewer).seats, seat.committed?, do: seat.name

        assert committed == ["Mara"]
      end
    end

    test "a committed Bridge cannot be written over" do
      {:ok, state, []} = commit(bridging(), "Mara", "cairn")

      assert {:error, :already_committed} = commit(state, "Mara", "beacon")
      assert Game.view(state, "seat-Mara").your_bridge == "cairn"
    end

    test "a Bridge is a word, and blank is not one" do
      assert {:error, :bridge_required} = commit(bridging(), "Mara", "   ")
      assert {:error, :bridge_required} = commit(bridging(), "Mara", "")
    end

    test "surrounding whitespace and shouting are not part of a Bridge" do
      {:ok, state, []} = commit(bridging(), "Mara", "  Cairn \n")

      assert Game.view(state, "seat-Mara").your_bridge == "cairn"
    end

    test "a Bridge from someone who holds no Seat here is not a Bridge" do
      assert {:error, :no_such_seat} = commit(bridging(), "Ada", "cairn")
    end
  end

  describe "the last commit" do
    test "asks for one assay per pair and starts the beat" do
      {state, effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])

      assert :beat in effects
      assert [{:assay, pair, request}] = assays(effects)
      assert Enum.sort(pair) == pair
      assert Enum.sort(pair) == Enum.sort(["seat-Mara", "seat-Jacob"])
      assert request.anchors == ["lantern", "harbour"]
      assert Enum.sort(request.bridges) == ["beacon", "cairn"]

      assert Game.view(state, nil).phase == :assaying
    end

    test "three Seats make three pairs, all asked for at once" do
      {_state, effects} =
        three_committed()

      assert length(assays(effects)) == 3
    end

    test "nothing is asked for until every Seat has committed" do
      {:ok, state, effects} = commit(bridging(), "Mara", "cairn")

      assert effects == []
      assert Game.view(state, nil).phase == :bridging
      assert Game.view(state, nil).reveal == nil
    end

    test "no Bridge may be written once the assay is running" do
      {state, _effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])

      assert {:error, :not_bridging} = commit(state, "Mara", "beacon")
    end
  end

  describe "the reveal" do
    test "waits for the verdict, then shows both Bridges to everyone" do
      {state, effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])

      assert Game.view(state, nil).reveal == nil

      state = grade(state, effects, [78])

      for viewer <- ["seat-Mara", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :reveal

        assert Enum.map(view.reveal.bridges, &{&1.name, &1.bridge}) == [
                 {"Mara", "cairn"},
                 {"Jacob", "beacon"}
               ]
      end
    end

    test "carries the closeness, the band and the Assayer's reasoning" do
      view = Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], [78]), nil)

      assert view.reveal.closeness == 78
      assert view.reveal.band == :meld
      assert view.reveal.melded? == true
      assert [pair] = view.reveal.pairs
      assert pair.names == ["Mara", "Jacob"]
      assert pair.closeness == 78
      assert pair.reasoning == "because"
      assert pair.melded? == true
    end

    test "the meld threshold is where a Meld starts and one under it is not one" do
      threshold = MeaningGame.Ladder.meld_threshold()

      assert Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], [threshold]), nil).reveal.melded?

      refute Game.view(
               revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], [threshold - 1]),
               nil
             ).reveal.melded?
    end

    test "each band is read at its own floor" do
      for {band, floor} <- MeaningGame.Ladder.bands() do
        view = Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], [floor]), nil)

        assert view.reveal.band == band
      end
    end

    test "a closeness off the scale is brought back onto it" do
      assert Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], [140]), nil).reveal.closeness ==
               100

      assert Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], [-20]), nil).reveal.closeness ==
               0
    end
  end

  describe "scoring at N seats" do
    setup do
      {state, effects} =
        three_committed()

      %{ungraded: state, effects: effects, state: grade(state, effects, [90, 60, 30])}
    end

    test "the headline number is the mean across every pair", %{state: state} do
      reveal = Game.view(state, nil).reveal

      assert Enum.map(reveal.pairs, & &1.closeness) == [90, 60, 30]
      assert reveal.closeness == 60
      assert reveal.band == :near
      refute reveal.melded?
    end

    test "the stage is told who melded with whom", %{state: state} do
      melded =
        for pair <- Game.view(state, nil).reveal.pairs, pair.melded?, do: pair.names

      assert melded == [["Mara", "Jacob"]]
    end

    test "the reveal waits for the last pair", ctx do
      partly_graded = grade(ctx.ungraded, Enum.take(assays(ctx.effects), 2), [90, 60])

      assert Game.view(partly_graded, nil).phase == :assaying
      assert Game.view(partly_graded, nil).reveal == nil
    end
  end

  describe "a verdict that never comes" do
    test "the Page still reveals, with no number and no Meld" do
      {state, effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      [{:assay, pair, _request}] = assays(effects)

      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{pair: pair}})
      reveal = Game.view(state, nil).reveal

      assert Game.view(state, nil).phase == :reveal
      assert reveal.closeness == nil
      assert reveal.band == nil
      assert reveal.melded? == false
      assert [pair_view] = reveal.pairs
      refute pair_view.graded?
      assert Enum.map(reveal.bridges, & &1.bridge) == ["cairn", "beacon"]
    end

    test "one ungraded pair does not cost the others their number" do
      {state, effects} =
        three_committed()

      [first | rest] = assays(effects)
      state = grade(state, rest, [60, 30])
      {:assay, pair, _request} = first
      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{pair: pair}})

      reveal = Game.view(state, nil).reveal

      assert reveal.closeness == 45
      assert Enum.map(reveal.pairs, & &1.graded?) == [false, true, true]
    end
  end

  describe "a verdict is a ruling, not a suggestion" do
    test "the grade that landed first is the grade that stands" do
      {state, effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      graded = grade(state, effects, [78])
      [{:assay, pair, _request}] = assays(effects)

      second_thought =
        {:verdict_received, %{pair: pair, closeness: 12, reasoning: "on reflection"}}

      assert {:ok, ^graded, []} = Game.apply(graded, second_thought)
      assert Game.view(graded, nil).reveal.closeness == 78
    end

    test "a verdict for a pair this Room does not have is refused" do
      {state, _effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])

      event = {:verdict_received, %{pair: ["seat-Ada", "seat-Zoe"], closeness: 90, reasoning: ""}}

      assert {:error, :no_verdict_expected} = Game.apply(state, event)
    end

    test "a verdict for a Page whose Bridges are not all in is refused" do
      {:ok, state, []} = commit(bridging(), "Mara", "cairn")

      pair = Enum.sort(["seat-Mara", "seat-Jacob"])
      event = {:verdict_received, %{pair: pair, closeness: 90, reasoning: ""}}

      assert {:error, :no_verdict_expected} = Game.apply(state, event)
    end
  end
end
