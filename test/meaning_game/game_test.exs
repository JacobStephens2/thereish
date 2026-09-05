defmodule MeaningGame.GameTest do
  @moduledoc """
  The rules, driven as a list of events and asserted on the projected view.

  Everything here goes through `init`, `apply` and `view`, because that is all a
  Room has to work with and all a later Page will have either. Where a test
  needs the Bridges that were sent for grading, it takes them out of the effects
  the rules emitted rather than assembling them itself — the Room has nothing
  else either.
  """
  use ExUnit.Case, async: true

  alias MeaningGame.Game
  alias MeaningGame.Ladder

  @page %{id: "test-page", bookends: ["lantern", "harbour"]}

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

  defp assays(effects), do: Enum.filter(effects, &match?({:assay, _request}, &1))

  defp chronicles(effects), do: Enum.filter(effects, &match?({:chronicle, _entry}, &1))

  # Grades the one assay the last commit asked for.
  defp grade(state, effects, closeness, furthest \\ nil) do
    {state, _effects} = graded(state, effects, closeness, furthest)

    state
  end

  # The same, keeping what the verdict left the Room owing — which is nothing at
  # all unless it was the verdict that closed the Page.
  #
  # An Assayer that grades names the two Bridges that landed furthest apart. A
  # test that does not care which two gets the first two in roster order, which
  # at two Seats is both of them.
  defp graded(state, effects, closeness, furthest) do
    [{:assay, request}] = assays(effects)

    event =
      {:verdict_received,
       %{
         closeness: closeness,
         reasoning: "because",
         furthest: furthest || Enum.take(request.bridges, 2),
         meta: %{model: "test", prompt_version: "v1", latency_ms: 12, cost_usd: 0.0001}
       }}

    {:ok, state, effects} = Game.apply(state, event)
    {state, effects}
  end

  # The whole Page in one line, for tests that are about the reveal rather than
  # the road to it.
  defp revealed(bridges, closeness) do
    {state, effects} = commit_all(bridging(), bridges)
    grade(state, effects, closeness)
  end

  # One attempt played all the way to a graded reveal, handing back whatever the
  # verdict left owing.
  defp attempt(state, bridges, closeness, furthest \\ nil) do
    {state, effects} = commit_all(state, bridges)

    graded(state, effects, closeness, furthest)
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
  # left to carry into. The Bridges differ every time so that the Bookends do.
  defp missed_through(count) do
    Enum.reduce(1..count, {bridging(), []}, fn n, {state, _effects} ->
      state = if n == 1, do: state, else: again(state)
      {w1, w2} = Enum.at(@miss_words, n - 1)

      attempt(state, [{"Melissa", w1}, {"Jacob", w2}], 10)
    end)
  end

  # Three Seats with every Bridge in: three words for the Assayer to read as one
  # set.
  defp three_committed do
    commit_all(bridging(["Melissa", "Jacob", "Ada"]), [
      {"Melissa", "cairn"},
      {"Jacob", "beacon"},
      {"Ada", "wharf"}
    ])
  end

  # Two couples at a table, every Bridge in: the evening this was built for.
  defp four_committed do
    commit_all(bridging(["Melissa", "Jacob", "Ada", "Ida"]), [
      {"Melissa", "cairn"},
      {"Jacob", "beacon"},
      {"Ada", "wharf"},
      {"Ida", "signal"}
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

    test "the player who got there first does not get the Bookends first" do
      state = Game.init(seat_limit: 2, seats: [seat("Melissa")], page: @page)

      assert Game.view(state, "seat-Melissa").bookends == nil
      refute inspect(Game.view(state, "seat-Melissa")) =~ "lantern"
    end

    test "a Room with no Page is waiting however full it is" do
      state = Game.init(seat_limit: 2, seats: [seat("Melissa"), seat("Jacob")])

      assert Game.view(state, nil).phase == :waiting
      assert Game.view(state, nil).bookends == nil
    end

    test "the last player to join starts the Page for everyone" do
      state =
        Game.init(seat_limit: 2, seats: [seat("Melissa")], page: @page)
        |> play([{:seat_joined, seat("Jacob")}])

      for viewer <- ["seat-Melissa", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :bridging
        assert view.bookends == ["lantern", "harbour"]
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

    test "phrases, digits, hyphens and apostrophes are legal bridges and 'Viking beaches' commits" do
      {:ok, state, []} = commit(bridging(), "Melissa", "Viking beaches")
      assert Game.view(state, "seat-Melissa").your_bridge == "viking beaches"

      {:ok, state2, []} = commit(bridging(), "Melissa", "ice-cream")
      assert Game.view(state2, "seat-Melissa").your_bridge == "ice-cream"

      {:ok, state3, []} = commit(bridging(), "Melissa", "rock 'n' roll")
      assert Game.view(state3, "seat-Melissa").your_bridge == "rock 'n' roll"

      {:ok, state4, []} = commit(bridging(), "Melissa", "apollo 11")
      assert Game.view(state4, "seat-Melissa").your_bridge == "apollo 11"
    end

    test "a Bridge sharing root with bookend is refused" do
      assert {:error, {:illegal_bridge, "\"lanterns\" shares a root with \"lantern\"."}} =
               commit(bridging(), "Melissa", "lanterns")

      assert {:error, {:illegal_bridge, "\"lantern\" shares a root with \"lantern\"."}} =
               commit(bridging(), "Melissa", "lantern")
    end

    test "in attempt 2, carried bridges and earlier attempt bridges are barred" do
      # Attempt 1: bookends are ["lantern", "harbour"].
      # Melissa bridges "cairn", Jacob bridges "beacon".
      # They do not meld (closeness 0).
      {revealed, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], 0)

      # Advance to attempt 2: carried bookends are ["cairn", "beacon"]
      attempt2 = again(revealed)

      assert attempt2.attempt == 2
      assert attempt2.bookends == ["cairn", "beacon"]
      assert Game.barred_words(attempt2) == ["cairn", "beacon", "lantern", "harbour"]
      assert Game.view(attempt2, nil).barred_words == ["cairn", "beacon", "lantern", "harbour"]

      # Carried bridge is barred as bookend
      assert {:error, {:illegal_bridge, "\"cairn\" shares a root with \"cairn\"."}} =
               commit(attempt2, "Melissa", "cairn")

      # Attempt 1's bookends are also barred
      assert {:error, {:illegal_bridge, "\"lantern\" shares a root with \"lantern\"."}} =
               commit(attempt2, "Melissa", "lantern")

      # "lava rock" after "lava" refused naming lava:
      # If attempt 1 had "lava", in attempt 2 "lava rock" is refused naming lava
      lava_page = %{@page | bookends: ["mountain", "sea"]}

      lava_bridging =
        Game.init(seat_limit: 2, seats: [seat("Melissa"), seat("Jacob")], page: lava_page)

      {revealed_lava, _effects} =
        attempt(lava_bridging, [{"Melissa", "lava"}, {"Jacob", "island"}], 0)

      attempt2_lava = again(revealed_lava)

      assert {:error, {:illegal_bridge, "\"lava rock\" shares a root with \"lava\"."}} =
               commit(attempt2_lava, "Melissa", "lava rock")
    end
  end

  describe "the last commit" do
    test "asks for exactly one assay and starts the beat" do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])

      assert :beat in effects
      assert [{:assay, request}] = assays(effects)
      assert request.bookends == ["lantern", "harbour"]

      # In roster order, the order the reveal shows them in, so that the
      # sentence the Assayer writes and the joke it makes name the words in the
      # order they are on the screen.
      assert request.bridges == ["cairn", "beacon"]

      assert Game.view(state, nil).phase == :assaying
    end

    test "four Seats are still one assay, carrying four Bridges in roster order" do
      {_state, effects} = four_committed()

      assert [{:assay, request}] = assays(effects)
      assert request.bridges == ["cairn", "beacon", "wharf", "signal"]
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

      state = grade(state, effects, 60)

      for viewer <- ["seat-Melissa", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :reveal

        assert Enum.map(view.reveal.bridges, &{&1.name, &1.bridge}) == [
                 {"Melissa", "cairn"},
                 {"Jacob", "beacon"}
               ]
      end
    end

    test "carries the closeness and the band, but no reasoning" do
      view = Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], 92), nil)

      assert view.reveal.closeness == 92
      assert view.reveal.band == :meld
      assert view.reveal.melded? == true
      assert view.reveal.graded? == true
      refute Map.has_key?(view.reveal, :reasoning)
    end

    test "the meld threshold is where a Meld starts and one under it is not one" do
      threshold = MeaningGame.Ladder.meld_threshold()

      assert Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], threshold), nil).reveal.melded?

      refute Game.view(
               revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], threshold - 1),
               nil
             ).reveal.melded?
    end

    test "each band is read at its own floor" do
      for {band, floor} <- MeaningGame.Ladder.bands() do
        view = Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], floor), nil)

        assert view.reveal.band == band
      end
    end

    test "a closeness off the scale is brought back onto it" do
      assert Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], 140), nil).reveal.closeness ==
               100

      assert Game.view(revealed([{"Melissa", "cairn"}, {"Jacob", "beacon"}], -20), nil).reveal.closeness ==
               0
    end
  end

  describe "scoring at N seats" do
    setup do
      {state, effects} = four_committed()

      %{
        ungraded: state,
        effects: effects,
        state: grade(state, effects, 60, ["beacon", "wharf"])
      }
    end

    test "one number for the whole table, not one per pair", %{state: state} do
      reveal = Game.view(state, nil).reveal

      assert reveal.closeness == 60
      assert reveal.band == :close
      refute reveal.melded?
      refute Map.has_key?(reveal, :pairs)
    end

    test "every Bridge is on the reveal, with the name that wrote it", %{state: state} do
      reveal = Game.view(state, "seat-Ada").reveal

      assert Enum.map(reveal.bridges, &{&1.name, &1.bridge}) == [
               {"Melissa", "cairn"},
               {"Jacob", "beacon"},
               {"Ada", "wharf"},
               {"Ida", "signal"}
             ]
    end

    test "one quip and no reasoning on the reveal, however many wrote", %{state: state} do
      reveal = Game.view(state, nil).reveal

      refute Map.has_key?(reveal, :reasoning)
      assert is_binary(reveal.quip) or is_nil(reveal.quip)
    end

    test "the two furthest words are named, and whose they are", %{state: state} do
      reveal = Game.view(state, nil).reveal

      assert Enum.map(reveal.furthest, &{&1.name, &1.bridge}) == [
               {"Jacob", "beacon"},
               {"Ada", "wharf"}
             ]
    end

    test "the Page melds when that one number reaches the meld band", ctx do
      melded = grade(ctx.ungraded, ctx.effects, MeaningGame.Ladder.meld_threshold())

      assert Game.view(melded, nil).reveal.melded?
      assert Game.view(melded, nil).phase == :closed
    end

    test "three Seats are one set as well, not three pairs" do
      {state, effects} = three_committed()

      assert [{:assay, request}] = assays(effects)
      assert request.bridges == ["cairn", "beacon", "wharf"]

      reveal = Game.view(grade(state, effects, 45, ["cairn", "wharf"]), nil).reveal

      assert reveal.closeness == 45
      assert length(reveal.bridges) == 3
      assert Enum.map(reveal.furthest, & &1.name) == ["Melissa", "Ada"]
    end

    test "the reveal waits for the Verdict", ctx do
      assert Game.view(ctx.ungraded, nil).phase == :assaying
      assert Game.view(ctx.ungraded, nil).reveal == nil
    end
  end

  describe "a verdict that never comes" do
    test "the Page still reveals, with no number and no Meld" do
      {state, _effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])

      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{}})
      reveal = Game.view(state, nil).reveal

      assert Game.view(state, nil).phase == :reveal
      assert reveal.closeness == nil
      assert reveal.band == nil
      assert reveal.melded? == false
      refute reveal.graded?
      assert Enum.map(reveal.bridges, & &1.bridge) == ["cairn", "beacon"]
    end

    test "at four Seats it is one absence rather than six" do
      {state, _effects} = four_committed()

      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{}})
      reveal = Game.view(state, nil).reveal

      refute reveal.graded?
      assert reveal.closeness == nil
      assert reveal.furthest == nil
      assert length(reveal.bridges) == 4
    end
  end

  describe "a miss carries forward" do
    test "the two failed Bridges become the next attempt's Bookends" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], 10)

      assert Game.view(state, nil).next_bookends == ["cairn", "beacon"]

      state = again(state)

      for viewer <- ["seat-Melissa", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :bridging
        assert view.bookends == ["cairn", "beacon"]
        assert view.attempt == %{number: 2, of: Game.attempt_cap()}
        assert view.reveal == nil
        assert view.your_bridge == nil
        assert Enum.map(view.seats, & &1.committed?) == [false, false]
      end
    end

    test "the Page keeps the Bookends it was authored with" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], 10)

      assert again(state).page.bookends == ["lantern", "harbour"]
    end

    test "the attempt that was played is kept, so the arc can be read at the end" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], 10)

      assert [first] = Game.view(again(state), nil).played
      assert first.number == 1
      assert first.bookends == ["lantern", "harbour"]
      assert Enum.map(first.bridges, & &1.bridge) == ["cairn", "beacon"]
      assert first.closeness == 10
      assert first.band == :miss
    end

    test "at four Seats it is the two the Assayer named, whoever wrote them" do
      {state, effects} = four_committed()
      state = grade(state, effects, 30, ["beacon", "signal"])

      # The Assayer read four words together and said these two are the ends of
      # the table. Nothing here recomputes that.
      assert Game.view(state, nil).next_bookends == ["beacon", "signal"]
      assert Game.view(state, nil).next_bookends_chosen? == true
      assert Game.view(again(state), nil).bookends == ["beacon", "signal"]
    end

    test "with no Verdict the first two in roster order carry, and the view says so" do
      {state, _effects} = four_committed()
      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{}})

      assert Game.view(state, nil).next_bookends == ["cairn", "beacon"]
      assert Game.view(state, nil).next_bookends_chosen? == false
      assert Game.view(again(state), nil).bookends == ["cairn", "beacon"]
    end

    test "a word nobody wrote is no choice: the roster carries, and the view says so" do
      {state, effects} = four_committed()
      state = grade(state, effects, 30, ["beacon", "lighthouse"])

      # "lighthouse" is a paraphrase of nobody's Bridge. Sending the table to an
      # Bookend none of them wrote would be a Page they were never asked to play.
      assert Game.view(state, nil).next_bookends == ["cairn", "beacon"]
      assert Game.view(state, nil).next_bookends_chosen? == false
      assert Game.view(state, nil).reveal.furthest == nil
    end

    test "a Page nobody could grade at all still carries something forward" do
      {state, _effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{}})

      assert Game.view(state, nil).next_bookends == ["cairn", "beacon"]
      assert Game.view(again(state), nil).bookends == ["cairn", "beacon"]
    end

    test "there is nothing to carry forward before the reveal" do
      state = bridging()

      assert Game.view(state, nil).next_bookends == nil

      assert {:error, :not_revealed} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Melissa"}})

      {:ok, state, []} = commit(state, "Melissa", "cairn")

      assert {:error, :not_revealed} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Melissa"}})
    end

    test "only a Seat in this Room may start the next attempt" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], 10)

      assert {:error, :no_such_seat} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Ada"}})
    end
  end

  describe "a Page closes" do
    test "the moment a Meld lands, however many attempts were left" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "cairo"}], 90)

      for viewer <- ["seat-Melissa", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :closed
        assert view.closed == %{because: :meld, attempt: 1}
        # The reveal is still up: closing a Page is an ending to the reveal, not
        # a screen that replaces it.
        assert view.reveal.closeness == 90
        assert view.reveal.melded?
        assert view.next_bookends == nil
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

      assert Enum.map(played, & &1.bookends) == [
               ["lantern", "harbour"],
               ["cairn", "beacon"],
               ["stone", "signal"]
             ]
    end
  end

  describe "the Chronicle is owed a closed Page" do
    test "with every attempt, every Bridge and every verdict on it" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], 10)

      {_state, effects} =
        attempt(again(state), [{"Melissa", "wharf"}, {"Jacob", "wharfinger"}], 92)

      assert [{:chronicle, entry}] = chronicles(effects)
      assert entry.page == @page
      assert entry.closed_because == :meld
      assert entry.melded? == true
      assert entry.closeness == 92

      assert [first, second] = entry.attempts
      assert first.number == 1
      assert first.bookends == ["lantern", "harbour"]

      assert Enum.map(first.bridges, &{&1.name, &1.bridge}) == [
               {"Melissa", "cairn"},
               {"Jacob", "beacon"}
             ]

      assert first.closeness == 10
      assert first.melded? == false

      assert second.bookends == ["cairn", "beacon"]
      assert second.melded? == true

      assert [verdict] = second.verdicts
      assert verdict.names == ["Melissa", "Jacob"]
      assert verdict.bridges == ["wharf", "wharfinger"]
      assert verdict.furthest == ["wharf", "wharfinger"]
      assert verdict.seat_ids == ["seat-Melissa", "seat-Jacob"]
      assert verdict.graded? == true
      assert verdict.closeness == 92
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
      {state, _effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
      state = again(elem(Game.apply(state, {:verdict_unavailable, %{}}), 1))

      {_state, effects} = attempt(state, [{"Melissa", "wharf"}, {"Jacob", "wharfinger"}], 92)

      assert [{:chronicle, entry}] = chronicles(effects)
      assert [first, _second] = entry.attempts
      assert [verdict] = first.verdicts
      assert verdict.graded? == false
      assert verdict.closeness == nil
      assert verdict.furthest == nil
      assert verdict.bridges == ["cairn", "beacon"]
    end

    test "and nothing is owed while the Page is still open" do
      {_state, effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], 10)

      assert chronicles(effects) == []
    end
  end

  describe "one more?" do
    setup do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "cairo"}], 90)

      %{closed: state}
    end

    test "starts a fresh Page in the same Room, with the same Seats", ctx do
      next = %{id: "test-page-2", bookends: ["desert", "mirror"]}

      assert {:ok, state, []} =
               Game.apply(ctx.closed, {:page_started, %{seat_id: "seat-Melissa", page: next}})

      view = Game.view(state, "seat-Melissa")

      assert view.phase == :bridging
      assert view.bookends == ["desert", "mirror"]
      assert view.attempt == %{number: 1, of: Game.attempt_cap()}
      assert view.reveal == nil
      assert view.closed == nil
      assert view.played == []
      assert names(view) == ["Melissa", "Jacob"]
    end

    test "cannot take a Page away from the couple in the middle of one" do
      {state, _effects} = attempt(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}], 10)
      next = %{id: "test-page-2", bookends: ["desert", "mirror"]}

      assert {:error, :page_open} =
               Game.apply(state, {:page_started, %{seat_id: "seat-Melissa", page: next}})

      assert {:error, :page_open} =
               Game.apply(bridging(), {:page_started, %{seat_id: "seat-Melissa", page: next}})
    end

    test "is a tap only someone in the Room can make", ctx do
      next = %{id: "test-page-2", bookends: ["desert", "mirror"]}

      assert {:error, :no_such_seat} =
               Game.apply(ctx.closed, {:page_started, %{seat_id: "seat-Ada", page: next}})
    end
  end

  describe "a verdict is a ruling, not a suggestion" do
    test "the grade that landed first is the grade that stands" do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
      graded = grade(state, effects, 78)

      second_thought =
        {:verdict_received, %{closeness: 12, reasoning: "on reflection", furthest: []}}

      assert {:ok, ^graded, []} = Game.apply(graded, second_thought)
      assert Game.view(graded, nil).reveal.closeness == 78
    end

    test "a verdict for an attempt the Page has moved on from is refused" do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
      moved_on = again(grade(state, effects, 10))

      late = {:verdict_received, %{closeness: 90, reasoning: "at last", furthest: []}}

      assert {:error, :no_verdict_expected} = Game.apply(moved_on, late)
    end

    test "a verdict for a Page whose Bridges are not all in is refused" do
      {:ok, state, []} = commit(bridging(), "Melissa", "cairn")

      event = {:verdict_received, %{closeness: 90, reasoning: "", furthest: []}}

      assert {:error, :no_verdict_expected} = Game.apply(state, event)
    end
  end

  describe "overruling a grade" do
    setup do
      {state, effects} = commit_all(bridging(), [{"Melissa", "cairn"}, {"Jacob", "beacon"}])
      %{revealed: grade(state, effects, 41)}
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

    test "a proposed overrule defaults to the meld floor read from the Ladder, not 100", ctx do
      {:ok, proposed, []} =
        Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Melissa"}})

      view = Game.view(proposed, "seat-Melissa")
      assert view.overrule.closeness == Ladder.meld_threshold()
      assert view.overrule.closeness == 90
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
      assert view.reveal.closeness == Ladder.meld_threshold()
      assert view.reveal.melded?
      assert view.reveal.overruled?
      assert view.phase == :closed
      assert view.closed == %{because: :meld, attempt: 1}
      assert view.overrule == nil

      # Emitted overrule effect with original and couple ruling
      assert {:overrule, overrule} = Enum.find(effects, &match?({:overrule, _}, &1))
      assert overrule.proposer_seat_id == "seat-Melissa"
      assert overrule.machine_closeness == 41
      assert overrule.couple_closeness == Ladder.meld_threshold()
      assert overrule.bookends == ["lantern", "harbour"]
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

    test "a four-Seat Room needs all four Seats to agree, and three is not enough" do
      {state, effects} = four_committed()
      revealed = grade(state, effects, 30)

      assert {:ok, p1, []} =
               Game.apply(revealed, {:overrule_proposed, %{seat_id: "seat-Melissa"}})

      assert Game.view(p1, nil).reveal.closeness == 30
      assert Game.view(p1, nil).overrule.pending?

      # Two of four, then three of four: still the machine's number.
      assert {:ok, p2, []} = Game.apply(p1, {:overrule_agreed, %{seat_id: "seat-Jacob"}})
      assert {:ok, p3, []} = Game.apply(p2, {:overrule_agreed, %{seat_id: "seat-Ada"}})

      assert Game.view(p3, nil).reveal.closeness == 30
      assert Game.view(p3, nil).overrule.pending?

      # The fourth agrees, and the table has ruled.
      assert {:ok, agreed, effects} =
               Game.apply(p3, {:overrule_agreed, %{seat_id: "seat-Ida"}})

      assert Game.view(agreed, nil).overrule == nil
      assert Game.view(agreed, nil).reveal.closeness == 90
      assert Game.view(agreed, nil).reveal.overruled?

      # The Precedent it rewrites is the one for the whole Bridge list.
      assert {:overrule, overrule} = Enum.find(effects, &match?({:overrule, _}, &1))
      assert overrule.bridges == ["cairn", "beacon", "wharf", "signal"]
    end

    test "a declined proposal clears it and leaves the grade alone at four Seats" do
      {state, effects} = four_committed()
      revealed = grade(state, effects, 30)

      {:ok, proposed, []} =
        Game.apply(revealed, {:overrule_proposed, %{seat_id: "seat-Melissa"}})

      assert {:ok, declined, []} =
               Game.apply(proposed, {:overrule_declined, %{seat_id: "seat-Ida"}})

      assert Game.view(declined, nil).overrule == nil
      assert Game.view(declined, nil).reveal.closeness == 30
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

  describe "the fairness tap (ticket 11)" do
    setup do
      {state, effects} =
        commit_all(bridging(), [{"Melissa", "dock"}, {"Jacob", "wharf"}])

      revealed = grade(state, effects, 62)
      %{revealed: revealed}
    end

    test "tapping fair at the reveal emits a fairness_tap effect with all required fields", ctx do
      assert {:ok, tapped, effects} =
               Game.apply(
                 ctx.revealed,
                 {:fairness_tapped, %{seat_id: "seat-Melissa", label: "fair"}}
               )

      assert [
               {:fairness_tap,
                %{
                  seat_id: "seat-Melissa",
                  attempt_number: 1,
                  bookends: ["lantern", "harbour"],
                  bridges: ["dock", "wharf"],
                  grade: 62,
                  band: "close",
                  model: "test",
                  prompt_version: "v1",
                  label: "fair"
                }}
             ] = effects

      assert Game.view(tapped, "seat-Melissa").your_tap == "fair"
      assert Game.view(tapped, "seat-Jacob").your_tap == nil
    end

    test "two seats can disagree about the same grade and both persist", ctx do
      assert {:ok, s1, [fair_effect]} =
               Game.apply(
                 ctx.revealed,
                 {:fairness_tapped, %{seat_id: "seat-Melissa", label: "fair"}}
               )

      assert {:ok, s2, [harsh_effect]} =
               Game.apply(s1, {:fairness_tapped, %{seat_id: "seat-Jacob", label: "too_harsh"}})

      assert match?({:fairness_tap, %{seat_id: "seat-Melissa", label: "fair"}}, fair_effect)
      assert match?({:fairness_tap, %{seat_id: "seat-Jacob", label: "too_harsh"}}, harsh_effect)

      assert Game.view(s2, "seat-Melissa").your_tap == "fair"
      assert Game.view(s2, "seat-Jacob").your_tap == "too_harsh"
    end

    test "tapping never blocks or delays the next attempt", ctx do
      {:ok, tapped, _} =
        Game.apply(
          ctx.revealed,
          {:fairness_tapped, %{seat_id: "seat-Melissa", label: "too_kind"}}
        )

      assert {:ok, advanced, []} =
               Game.apply(tapped, {:attempt_advanced, %{seat_id: "seat-Jacob"}})

      view = Game.view(advanced, "seat-Melissa")
      assert view.attempt.number == 2
      assert view.phase == :bridging
      assert view.your_tap == nil
    end

    test "skipping the tap is normal: attempt advances without any tap", ctx do
      assert {:ok, advanced, []} =
               Game.apply(ctx.revealed, {:attempt_advanced, %{seat_id: "seat-Jacob"}})

      assert Game.view(advanced, "seat-Melissa").attempt.number == 2
    end

    test "at four Seats the tap records the one grade and every Bridge under it" do
      {state, effects} = four_committed()
      revealed = grade(state, effects, 45)

      assert {:ok, _tapped, [{:fairness_tap, tap}]} =
               Game.apply(
                 revealed,
                 {:fairness_tapped, %{seat_id: "seat-Ida", label: "too_harsh"}}
               )

      assert tap.bridges == ["cairn", "beacon", "wharf", "signal"]
      assert tap.grade == 45
      assert tap.band == "adjacent"
      assert tap.label == "too_harsh"
    end

    test "cannot tap when not revealed" do
      state = bridging()

      assert {:error, :not_revealed} =
               Game.apply(state, {:fairness_tapped, %{seat_id: "seat-Melissa", label: "fair"}})
    end

    test "rejects an invalid label", ctx do
      assert {:error, :invalid_label} =
               Game.apply(
                 ctx.revealed,
                 {:fairness_tapped, %{seat_id: "seat-Melissa", label: "bogus"}}
               )
    end
  end
end
