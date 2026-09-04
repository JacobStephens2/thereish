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
  defp bridging(names \\ ["Melissa", "Jacob"]) do
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

  defp chronicles(effects), do: Enum.filter(effects, &match?({:chronicle, _entry}, &1))

  # Grades the pairs in the order they were asked for.
  defp grade(state, effects, closenesses) do
    {state, _effects} = graded(state, effects, closenesses)

    state
  end

  # The same, keeping what the last verdict left the Room owing — which is
  # nothing at all unless that verdict was the one that closed the Page.
  defp graded(state, effects, closenesses) do
    effects
    |> assays()
    |> Enum.zip(closenesses)
    |> Enum.reduce({state, []}, fn {{:assay, pair, _request}, closeness}, {state, _effects} ->
      event =
        {:verdict_received,
         %{
           pair: pair,
           closeness: closeness,
           reasoning: "because",
           meta: %{model: "test", prompt_version: "v1", latency_ms: 12, cost_usd: 0.0001}
         }}

      {:ok, state, effects} = Game.apply(state, event)
      {state, effects}
    end)
  end

  # The whole Page in one line, for tests that are about the reveal rather than
  # the road to it.
  defp revealed(bridges, closenesses) do
    {state, effects} = commit_all(bridging(), bridges)
    grade(state, effects, closenesses)
  end

  # One attempt played all the way to a graded reveal, handing back whatever the
  # last verdict left owing.
  defp attempt(state, bridges, closenesses) do
    {state, effects} = commit_all(state, bridges)

    graded(state, effects, closenesses)
  end

  defp again(state, name \\ "Melissa") do
    {:ok, state, []} = Game.apply(state, {:attempt_advanced, %{seat_id: "seat-" <> name}})

    state
  end

  @miss_words [
    {"cairn", "beacon"},
    {"stone", "signal"},
    {"granite", "flare"},
    {"rock", "torch"},
    {"boulder", "light"}
  ]

  # Misses `count` times over, carrying forward each time there is an attempt
  # left to carry into. The Bridges differ every time so that the Anchors do.
  defp missed_through(count) do
    Enum.reduce(1..count, {bridging(), []}, fn n, {state, _effects} ->
      state = if n == 1, do: state, else: again(state)
      {w1, w2} = Enum.at(@miss_words, n - 1)

      attempt(state, [{"Melissa", w1}, {"Jacob", w2}], [10])
    end)
  end

  # Three Seats with every Bridge in: the Page that has three pairs to grade.
  defp three_committed do
    commit_all(bridging(["Melissa", "Jacob", "Ada"]), [
      {"Melissa", "cairn"},
      {"Jacob", "beacon"},
      {"Ada", "wharf"}
    ])
  end

  describe "seats are a list of N" do
    test "a Room of three seats takes a third player the same way it took the first two" do
      state =
        Game.init(seat_limit: 3)
        |> play([
          {:seat_joined, seat("Melissa")},
          {:seat_joined, seat("Jacob")},
          {:seat_joined, seat("Ada")}
        ])

      assert names(Game.view(state, nil)) == ["Melissa", "Jacob", "Ada"]
      assert Game.view(state, nil).open_seats == 0
    end

    test "a Room turns away a player once its seats are gone" do
      state =
        Game.init(seat_limit: 2)
        |> play([{:seat_joined, seat("Melissa")}, {:seat_joined, seat("Jacob")}])

      assert {:error, :room_full} = Game.apply(state, {:seat_joined, seat("Ada")})
    end

    test "existing seats are restored without being replayed" do
      state = Game.init(seat_limit: 2, seats: [seat("Melissa"), seat("Jacob")])

      assert names(Game.view(state, nil)) == ["Melissa", "Jacob"]
      assert Game.view(state, nil).open_seats == 0
    end
  end

  describe "rejoining" do
    test "a seat already in the Room joining again changes nothing" do
      state = play(Game.init(seat_limit: 2), [{:seat_joined, seat("Melissa")}])

      assert {:ok, ^state, []} = Game.apply(state, {:seat_joined, seat("Melissa")})
    end

    test "a full Room still takes a rejoin from a seat it already holds" do
      state = Game.init(seat_limit: 1, seats: [seat("Melissa")])

      assert {:ok, ^state, []} = Game.apply(state, {:seat_joined, seat("Melissa")})
    end
  end

  describe "view" do
    setup do
      %{state: Game.init(seat_limit: 3, seats: [seat("Melissa"), seat("Jacob")])}
    end

    test "every viewer sees the same roster in the same order", %{state: state} do
      assert names(Game.view(state, "seat-Melissa")) == ["Melissa", "Jacob"]
      assert names(Game.view(state, "seat-Jacob")) == ["Melissa", "Jacob"]
      assert names(Game.view(state, nil)) == ["Melissa", "Jacob"]
    end

    test "each seat is told which one is its own", %{state: state} do
      view = Game.view(state, "seat-Melissa")

      assert view.you.name == "Melissa"
      assert view.seats |> Enum.filter(& &1.you?) |> Enum.map(& &1.name) == ["Melissa"]
    end

    test "a viewer holding no seat is nobody in the roster", %{state: state} do
      view = Game.view(state, nil)

      assert view.you == nil
      refute Enum.any?(view.seats, & &1.you?)
    end

    test "the view counts the seats still open", %{state: state} do
      view = Game.view(state, "seat-Melissa")

      assert view.seat_limit == 3
      assert view.open_seats == 1
    end
  end

  describe "before the Page starts" do
    test "a Room still short a player is waiting rather than bridging" do
      state = Game.init(seat_limit: 2, seats: [seat("Melissa")], page: @page)

      assert Game.view(state, "seat-Melissa").phase == :waiting
      assert {:error, :not_bridging} = commit(state, "Melissa", "cairn")
    end

    test "the player who got there first does not get the Anchors first" do
      state = Game.init(seat_limit: 2, seats: [seat("Melissa")], page: @page)

      assert Game.view(state, "seat-Melissa").anchors == nil
      refute inspect(Game.view(state, "seat-Melissa")) =~ "lantern"
    end

    test "a Room with no Page is waiting however full it is" do
      state = Game.init(seat_limit: 2, seats: [seat("Melissa"), seat("Jacob")])

      assert Game.view(state, nil).phase == :waiting
      assert Game.view(state, nil).anchors == nil
    end

    test "the last player to join starts the Page for everyone" do
      state =
        Game.init(seat_limit: 2, seats: [seat("Melissa")], page: @page)
        |> play([{:seat_joined, seat("Jacob")}])

      for viewer <- ["seat-Melissa", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :bridging
        assert view.anchors == ["lantern", "harbour"]
      end
    end
  end

  describe "writing a Bridge" do
    test "a Seat's own Bridge is its own to see" do
      {:ok, state, []} = commit(bridging(), "Melissa", "cairn")

      assert Game.view(state, "seat-Melissa").your_bridge == "cairn"
    end

    test "an uncommitted Bridge is invisible to every other Seat" do
      {:ok, state, []} = commit(bridging(), "Melissa", "cairn")

      assert Game.view(state, "seat-Jacob").your_bridge == nil
      assert Game.view(state, nil).your_bridge == nil

      # Not merely absent from the field it would be read out of: nowhere in
      # what the other phone or the stage is handed.
      refute inspect(Game.view(state, "seat-Jacob")) =~ "cairn"
      refute inspect(Game.view(state, nil)) =~ "cairn"
    end

    test "every Seat sees that another has committed without seeing what it wrote" do
      {:ok, state, []} = commit(bridging(), "Melissa", "cairn")

      for viewer <- ["seat-Melissa", "seat-Jacob", nil] do
        committed = for seat <- Game.view(state, viewer).seats, seat.committed?, do: seat.name

        assert committed == ["Melissa"]
      end
    end

    test "a committed Bridge cannot be written over" do
      {:ok, state, []} = commit(bridging(), "Melissa", "cairn")

      assert {:error, :already_committed} = commit(state, "Melissa", "beacon")
      assert Game.view(state, "seat-Melissa").your_bridge == "cairn"
    end

    test "a Bridge is a word, and blank is not one" do
      assert {:error, :bridge_required} = commit(bridging(), "Melissa", "   ")
      assert {:error, :bridge_required} = commit(bridging(), "Melissa", "")
    end

    test "surrounding whitespace and shouting are not part of a Bridge" do
      {:ok, state, []} = commit(bridging(), "Melissa", "  Cairn \n")

      assert Game.view(state, "seat-Melissa").your_bridge == "cairn"
    end

    test "a Bridge from someone who holds no Seat here is not a Bridge" do
      assert {:error, :no_such_seat} = commit(bridging(), "Ada", "cairn")
    end
  end

  describe "the last commit" do
    test "asks for one assay per pair and starts the beat" do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])

      assert :beat in effects
      assert [{:assay, pair, request}] = assays(effects)
      assert Enum.sort(pair) == pair
      assert Enum.sort(pair) == Enum.sort(["seat-Melissa", "seat-Jacob"])
      assert request.anchors == ["lantern", "harbour"]

      # In roster order, not in the pair key's order. The Assayer writes a
      # sentence and a joke naming both words, and they should read in the order
      # the reveal shows them rather than in whatever order two Seat ids happen
      # to sort in.
      assert request.bridges == ["cairn", "beacon"]

      assert Game.view(state, nil).phase == :assaying
    end

    test "three Seats make three pairs, all asked for at once" do
      {_state, effects} =
        three_committed()

      assert length(assays(effects)) == 3
    end

    test "nothing is asked for until every Seat has committed" do
      {:ok, state, effects} = commit(bridging(), "Melissa", "cairn")

      assert effects == []
      assert Game.view(state, nil).phase == :bridging
      assert Game.view(state, nil).reveal == nil
    end

    test "no Bridge may be written once the assay is running" do
      {state, _effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])

      assert {:error, :not_bridging} = commit(state, "Melissa", "beacon")
    end
  end

  describe "the reveal" do
    test "waits for the verdict, then shows both Bridges to everyone" do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])

      assert Game.view(state, nil).reveal == nil

      state = grade(state, effects, [60])

      for viewer <- ["seat-Melissa", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :reveal

        assert Enum.map(view.reveal.bridges, &{&1.name, &1.bridge}) == [
                 {"Melissa", "cairn"},
                 {"Jacob", "beacon"}
               ]
      end
    end

    test "carries the closeness, the band and the Assayer's reasoning" do
      view = Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], [78]), nil)

      assert view.reveal.closeness == 78
      assert view.reveal.band == :meld
      assert view.reveal.melded? == true
      assert [pair] = view.reveal.pairs
      assert pair.names == ["Melissa", "Jacob"]
      assert pair.closeness == 78
      assert pair.reasoning == "because"
      assert pair.melded? == true
    end

    test "the meld threshold is where a Meld starts and one under it is not one" do
      threshold = MeaningGame.Ladder.meld_threshold()

      assert Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], [threshold]), nil).reveal.melded?

      refute Game.view(
               revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], [threshold - 1]),
               nil
             ).reveal.melded?
    end

    test "each band is read at its own floor" do
      for {band, floor} <- MeaningGame.Ladder.bands() do
        view = Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], [floor]), nil)

        assert view.reveal.band == band
      end
    end

    test "a closeness off the scale is brought back onto it" do
      assert Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], [140]), nil).reveal.closeness ==
               100

      assert Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], [-20]), nil).reveal.closeness ==
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

      assert melded == [["Melissa", "Jacob"]]
    end

    test "the reveal waits for the last pair", ctx do
      partly_graded = grade(ctx.ungraded, Enum.take(assays(ctx.effects), 2), [90, 60])

      assert Game.view(partly_graded, nil).phase == :assaying
      assert Game.view(partly_graded, nil).reveal == nil
    end
  end

  describe "a verdict that never comes" do
    test "the Page still reveals, with no number and no Meld" do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
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

  describe "a miss carries forward" do
    test "the two failed Bridges become the next attempt's Anchors" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], [10])

      assert Game.view(state, nil).next_anchors == ["cairn", "beacon"]

      state = again(state)

      for viewer <- ["seat-Melissa", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :bridging
        assert view.anchors == ["cairn", "beacon"]
        assert view.attempt == %{number: 2, of: Game.attempt_cap()}
        assert view.reveal == nil
        assert view.your_bridge == nil
        assert Enum.map(view.seats, & &1.committed?) == [false, false]
      end
    end

    test "the Page keeps the Anchors it was authored with" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], [10])

      assert again(state).page.anchors == ["lantern", "harbour"]
    end

    test "the attempt that was played is kept, so the arc can be read at the end" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], [10])

      assert [first] = Game.view(again(state), nil).played
      assert first.number == 1
      assert first.anchors == ["lantern", "harbour"]
      assert Enum.map(first.bridges, & &1.bridge) == ["cairn", "beacon"]
      assert first.closeness == 10
      assert first.band == :miss
    end

    test "at three Seats it is the pair that missed by the most" do
      {state, effects} = three_committed()
      state = grade(state, effects, [90, 60, 30])

      # Melissa + Jacob 90, Melissa + Ada 60, Jacob + Ada 30. The widest gap is
      # the one worth asking them to bridge, and Melissa's Bridge is not in it.
      assert Game.view(state, nil).next_anchors == ["beacon", "wharf"]
      assert Game.view(again(state), nil).anchors == ["beacon", "wharf"]
    end

    test "a pair the Assayer could not grade is not the widest gap" do
      {state, effects} = three_committed()
      [first | rest] = assays(effects)
      {:assay, pair, _request} = first
      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{pair: pair}})
      state = grade(state, rest, [60, 30])

      # An unknown is not a miss, so the ungraded Melissa + Jacob pair loses to
      # the graded 30.
      assert Game.view(state, nil).next_anchors == ["beacon", "wharf"]
    end

    test "a Page nobody could grade at all still carries something forward" do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
      [{:assay, pair, _request}] = assays(effects)
      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{pair: pair}})

      assert Game.view(state, nil).next_anchors == ["cairn", "beacon"]
      assert Game.view(again(state), nil).anchors == ["cairn", "beacon"]
    end

    test "there is nothing to carry forward before the reveal" do
      state = bridging()

      assert Game.view(state, nil).next_anchors == nil

      assert {:error, :not_revealed} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Melissa"}})

      {:ok, state, []} = commit(state, "Melissa", "cairn")

      assert {:error, :not_revealed} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Melissa"}})
    end

    test "only a Seat in this Room may start the next attempt" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], [10])

      assert {:error, :no_such_seat} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Ada"}})
    end
  end

  describe "a Page closes" do
    test "the moment a Meld lands, however many attempts were left" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "cairo"}], [80])

      for viewer <- ["seat-Melissa", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :closed
        assert view.closed == %{because: :meld, attempt: 1}
        # The reveal is still up: closing a Page is an ending to the reveal, not
        # a screen that replaces it.
        assert view.reveal.closeness == 80
        assert view.reveal.melded?
        assert view.next_anchors == nil
      end
    end

    test "when the last attempt is spent, unmelded" do
      {state, _effects} = missed_through(Game.attempt_cap())
      view = Game.view(state, nil)

      assert view.phase == :closed
      assert view.closed == %{because: :attempts_spent, attempt: Game.attempt_cap()}
      assert view.reveal.melded? == false
      assert view.reveal.closeness == 10
    end

    test "one attempt short of the cap it is still open" do
      {state, _effects} = missed_through(Game.attempt_cap() - 1)

      assert Game.view(state, nil).phase == :reveal
      assert Game.view(state, nil).closed == nil
    end

    test "and a closed Page takes no more attempts and no more Bridges" do
      {state, _effects} = missed_through(Game.attempt_cap())

      assert {:error, :page_closed} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Melissa"}})

      assert {:error, :not_bridging} = commit(state, "Melissa", "cairn")
    end

    test "with the whole arc of it readable" do
      {state, _effects} = missed_through(3)
      played = Game.view(again(state), nil).played

      assert Enum.map(played, & &1.number) == [1, 2, 3]

      assert Enum.map(played, & &1.anchors) == [
               ["lantern", "harbour"],
               ["cairn", "beacon"],
               ["stone", "signal"]
             ]
    end
  end

  describe "the Chronicle is owed a closed Page" do
    test "with every attempt, every Bridge and every verdict on it" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], [10])

      {_state, effects} =
        attempt(again(state), [{"Melissa", "wharf"}, {"Jacob", "wharfinger"}], [82])

      assert [{:chronicle, entry}] = chronicles(effects)
      assert entry.page == @page
      assert entry.closed_because == :meld
      assert entry.melded? == true
      assert entry.closeness == 82

      assert [first, second] = entry.attempts
      assert first.number == 1
      assert first.anchors == ["lantern", "harbour"]

      assert Enum.map(first.bridges, &{&1.name, &1.bridge}) == [
               {"Melissa", "cairn"},
               {"Jacob", "beacon"}
             ]

      assert first.closeness == 10
      assert first.melded? == false

      assert second.anchors == ["cairn", "beacon"]
      assert second.melded? == true

      assert [verdict] = second.verdicts
      assert verdict.names == ["Melissa", "Jacob"]
      assert verdict.bridges == ["wharf", "wharfinger"]
      assert verdict.seat_ids == ["seat-Melissa", "seat-Jacob"]
      assert verdict.graded? == true
      assert verdict.closeness == 82
      assert verdict.band == :meld
      assert verdict.reasoning == "because"
      assert verdict.meta.model == "test"
      assert verdict.meta.prompt_version == "v1"
      assert verdict.meta.latency_ms == 12
      assert verdict.meta.cost_usd == 0.0001
    end

    test "when it closes unmelded too" do
      {_state, effects} = missed_through(Game.attempt_cap())

      assert [{:chronicle, entry}] = chronicles(effects)
      assert entry.closed_because == :attempts_spent
      assert entry.melded? == false
      assert length(entry.attempts) == Game.attempt_cap()
    end

    test "and a verdict that never came is a row rather than a gap" do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
      [{:assay, pair, _request}] = assays(effects)
      state = again(elem(Game.apply(state, {:verdict_unavailable, %{pair: pair}}), 1))

      {_state, effects} = attempt(state, [{"Melissa", "wharf"}, {"Jacob", "wharfinger"}], [82])

      assert [{:chronicle, entry}] = chronicles(effects)
      assert [first, _second] = entry.attempts
      assert [verdict] = first.verdicts
      assert verdict.graded? == false
      assert verdict.closeness == nil
      assert verdict.bridges == ["cairn", "beacon"]
    end

    test "and nothing is owed while the Page is still open" do
      {_state, effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], [10])

      assert chronicles(effects) == []
    end
  end

  describe "one more?" do
    setup do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "cairo"}], [80])

      %{closed: state}
    end

    test "starts a fresh Page in the same Room, with the same Seats", ctx do
      next = %{id: "test-page-2", anchors: ["desert", "mirror"]}

      assert {:ok, state, []} =
               Game.apply(ctx.closed, {:page_started, %{seat_id: "seat-Melissa", page: next}})

      view = Game.view(state, "seat-Melissa")

      assert view.phase == :bridging
      assert view.anchors == ["desert", "mirror"]
      assert view.attempt == %{number: 1, of: Game.attempt_cap()}
      assert view.reveal == nil
      assert view.closed == nil
      assert view.played == []
      assert names(view) == ["Melissa", "Jacob"]
    end

    test "cannot take a Page away from the couple in the middle of one" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], [10])
      next = %{id: "test-page-2", anchors: ["desert", "mirror"]}

      assert {:error, :page_open} =
               Game.apply(state, {:page_started, %{seat_id: "seat-Melissa", page: next}})

      assert {:error, :page_open} =
               Game.apply(bridging(), {:page_started, %{seat_id: "seat-Melissa", page: next}})
    end

    test "is a tap only someone in the Room can make", ctx do
      next = %{id: "test-page-2", anchors: ["desert", "mirror"]}

      assert {:error, :no_such_seat} =
               Game.apply(ctx.closed, {:page_started, %{seat_id: "seat-Ada", page: next}})
    end
  end

  describe "a verdict is a ruling, not a suggestion" do
    test "the grade that landed first is the grade that stands" do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
      graded = grade(state, effects, [78])
      [{:assay, pair, _request}] = assays(effects)

      second_thought =
        {:verdict_received, %{pair: pair, closeness: 12, reasoning: "on reflection"}}

      assert {:ok, ^graded, []} = Game.apply(graded, second_thought)
      assert Game.view(graded, nil).reveal.closeness == 78
    end

    test "a verdict for a pair this Room does not have is refused" do
      {state, _effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])

      event = {:verdict_received, %{pair: ["seat-Ada", "seat-Zoe"], closeness: 90, reasoning: ""}}

      assert {:error, :no_verdict_expected} = Game.apply(state, event)
    end

    test "a verdict for a Page whose Bridges are not all in is refused" do
      {:ok, state, []} = commit(bridging(), "Melissa", "cairn")

      pair = Enum.sort(["seat-Melissa", "seat-Jacob"])
      event = {:verdict_received, %{pair: pair, closeness: 90, reasoning: ""}}

      assert {:error, :no_verdict_expected} = Game.apply(state, event)
    end
  end

  describe "overruling a grade" do
    setup do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
      revealed = grade(state, effects, [41])
      pair = hd(assays(effects)) |> elem(1)

      %{revealed: revealed, pair: pair}
    end

    test "any Seat can propose an overrule from the reveal", ctx do
      assert {:ok, state, []} =
               Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Melissa"}})

      # The proposal is pending, and the grade is untouched
      assert Game.view(state, nil).reveal.closeness == 41

      melissa_view = Game.view(state, "seat-Melissa")
      assert melissa_view.overrule.pending?
      assert melissa_view.overrule.proposer_id == "seat-Melissa"
      assert melissa_view.overrule.proposer_name == "Melissa"
      assert melissa_view.overrule.you_proposed?
      assert melissa_view.overrule.you_agreed?

      jacob_view = Game.view(state, "seat-Jacob")
      assert jacob_view.overrule.pending?
      assert jacob_view.overrule.proposer_id == "seat-Melissa"
      refute jacob_view.overrule.you_proposed?
      refute jacob_view.overrule.you_agreed?

      stage_view = Game.view(state, nil)
      assert stage_view.overrule.pending?
      assert stage_view.overrule.proposer_name == "Melissa"
      refute stage_view.overrule.you_proposed?
      refute stage_view.overrule.you_agreed?
    end

    test "cannot propose an overrule before the reveal" do
      state = bridging()

      assert {:error, :not_revealed} =
               Game.apply(state, {:overrule_proposed, %{seat_id: "seat-Melissa"}})
    end

    test "someone not in the Room cannot propose an overrule", ctx do
      assert {:error, :no_such_seat} =
               Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Ada"}})
    end

    test "an overrule takes effect only when every Seat agrees (unanimity)", ctx do
      {:ok, proposed, []} =
        Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Melissa"}})

      # Proposer alone does not rewrite the grade
      assert Game.view(proposed, nil).reveal.closeness == 41

      # Second seat agrees -> all 2 seats agree -> overrule takes effect!
      assert {:ok, agreed, effects} =
               Game.apply(proposed, {:overrule_agreed, %{seat_id: "seat-Jacob"}})

      view = Game.view(agreed, nil)
      assert view.reveal.closeness == 100
      assert view.reveal.melded?
      assert view.reveal.pairs |> hd() |> Map.get(:overruled?)
      assert view.phase == :closed
      assert view.closed == %{because: :meld, attempt: 1}
      assert view.overrule == nil

      # Emitted overrule effect with original and couple ruling
      assert {:overrule, overrule} = Enum.find(effects, &match?({:overrule, _}, &1))
      assert overrule.proposer_seat_id == "seat-Melissa"
      assert overrule.machine_closeness == 41
      assert overrule.couple_closeness == 100
      assert overrule.anchors == ["lantern", "harbour"]
      assert overrule.bridges == ["cairn", "beacon"]

      # And because it melded and closed, the Chronicle is owed
      assert {:chronicle, entry} = Enum.find(effects, &match?({:chronicle, _}, &1))
      assert entry.closed_because == :meld
      assert entry.melded?
    end

    test "a declined proposal leaves the grade untouched", ctx do
      {:ok, proposed, []} =
        Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Melissa"}})

      assert {:ok, declined, effects} =
               Game.apply(proposed, {:overrule_declined, %{seat_id: "seat-Jacob"}})

      assert effects == []
      view = Game.view(declined, nil)
      assert view.reveal.closeness == 41
      assert view.overrule == nil
      refute view.reveal.melded?
    end

    test "a three-Seat Room needs all three Seats to agree" do
      {state, effects} = three_committed()
      revealed = grade(state, effects, [40, 30, 20])

      assert {:ok, p1, []} =
               Game.apply(revealed, {:overrule_proposed, %{seat_id: "seat-Melissa"}})

      assert Game.view(p1, nil).reveal.closeness == 30
      assert Game.view(p1, nil).overrule.pending?

      # Second seat agrees: 2 of 3, still pending!
      assert {:ok, p2, []} =
               Game.apply(p1, {:overrule_agreed, %{seat_id: "seat-Jacob"}})

      assert Game.view(p2, nil).reveal.closeness == 30
      assert Game.view(p2, nil).overrule.pending?

      # Third seat agrees: 3 of 3, now takes effect!
      assert {:ok, agreed, effects} =
               Game.apply(p2, {:overrule_agreed, %{seat_id: "seat-Ada"}})

      assert Game.view(agreed, nil).overrule == nil
      assert Enum.any?(effects, &match?({:overrule, _}, &1))
    end

    test "the proposal expires cleanly if the Page moves on", ctx do
      {:ok, proposed, []} =
        Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Melissa"}})

      assert Game.view(proposed, nil).overrule.pending?

      # Next attempt starts without anyone agreeing
      assert {:ok, advanced, []} =
               Game.apply(proposed, {:attempt_advanced, %{seat_id: "seat-Jacob"}})

      view = Game.view(advanced, nil)
      assert view.attempt.number == 2
      assert view.phase == :bridging
      assert view.overrule == nil
    end
  end
end
