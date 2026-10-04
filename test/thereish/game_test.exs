defmodule Thereish.GameTest do
  @moduledoc """
  The rules, driven as a list of events and asserted on the projected view.

  Everything here goes through `init`, `apply` and `view`, because that is all a
  Room has to work with and all a later Page will have either. Where a test
  needs the Bridges that were sent for grading, it takes them out of the effects
  the rules emitted rather than assembling them itself — the Room has nothing
  else either.
  """
  use ExUnit.Case, async: true

  alias Thereish.Chronicle.Document
  alias Thereish.Chronicle.Entry
  alias Thereish.Game
  alias Thereish.Ladder
  alias Thereish.Mask

  @page %Document{bookends: ["lantern", "harbour"]}

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

  defp again(state, name \\ "Mara") do
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

      attempt(state, [{"Mara", w1}, {"Jacob", w2}], 10)
    end)
  end

  # Three Seats with every Bridge in: three words for the Assayer to read as one
  # set.
  defp three_committed do
    commit_all(bridging(["Mara", "Jacob", "Ada"]), [
      {"Mara", "cairn"},
      {"Jacob", "beacon"},
      {"Ada", "wharf"}
    ])
  end

  # Two couples at a table, every Bridge in: the evening this was built for.
  defp four_committed do
    commit_all(bridging(["Mara", "Jacob", "Ada", "Ida"]), [
      {"Mara", "cairn"},
      {"Jacob", "beacon"},
      {"Ada", "wharf"},
      {"Ida", "signal"}
    ])
  end

  # Four Seats on the two-Bookend rule: furthest pair carries, roster fallback.
  defp four_two_bookends do
    Game.init(
      seat_limit: 4,
      seats: Enum.map(["Mara", "Jacob", "Ada", "Ida"], &seat/1),
      page: %{@page | full_table: false},
      full_table: false
    )
  end

  defp four_committed_two do
    commit_all(four_two_bookends(), [
      {"Mara", "cairn"},
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

    test "the player who got there first does not get the Bookends first" do
      state = Game.init(seat_limit: 2, seats: [seat("Mara")], page: @page)

      assert Game.view(state, "seat-Mara").bookends == nil
      refute inspect(Game.view(state, "seat-Mara")) =~ "lantern"
    end

    test "a Room with no Page is giving when full, waiting when not full" do
      not_full = Game.init(seat_limit: 2, seats: [seat("Mara")])
      assert Game.view(not_full, nil).phase == :waiting

      full = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])
      assert Game.view(full, nil).phase == :giving
      assert Game.view(full, nil).bookends == nil
    end

    test "the last player to join starts the Page for everyone" do
      state =
        Game.init(seat_limit: 2, seats: [seat("Mara")], page: @page)
        |> play([{:seat_joined, seat("Jacob")}])

      for viewer <- ["seat-Mara", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :bridging
        assert view.bookends == ["lantern", "harbour"]
      end
    end
  end

  describe "giving and writing a Page (ticket 02)" do
    setup do
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])
      %{state: state}
    end

    test "full Room with no Page is in giving phase", %{state: state} do
      assert Game.view(state, "seat-Mara").phase == :giving
      assert Game.view(state, "seat-Jacob").phase == :giving
      assert Game.view(state, nil).phase == :giving
    end

    test "validates gives: blank, too long, not seated, already committed", %{state: state} do
      assert {:error, :give_required} =
               Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "   "}})

      long_give = String.duplicate("a", 121)

      assert {:error, :give_too_long} =
               Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: long_give}})

      assert {:error, :no_such_seat} =
               Game.apply(state, {:give_committed, %{seat_id: "seat-Ada", give: "ocean"}})

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "ocean"}})

      assert {:error, :already_committed} =
               Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "mountain"}})
    end

    test "first Give appears only in giver's view; others see gives_in count", %{state: state} do
      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      mara_view = Game.view(state, "seat-Mara")
      jacob_view = Game.view(state, "seat-Jacob")
      stage_view = Game.view(state, nil)

      assert mara_view.your_give == "lighthouse"
      assert mara_view.gives_in == 1
      assert mara_view.phase == :giving

      assert jacob_view.your_give == nil
      assert jacob_view.gives_in == 1
      assert jacob_view.phase == :giving

      assert stage_view.your_give == nil
      assert stage_view.gives_in == 1
      assert stage_view.phase == :giving
    end

    test "the last Give owes exactly one Author effect carrying every Give in roster order with names",
         %{state: state} do
      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      assert {:ok, state, [author_effect]} =
               Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      assert {:author, request} = author_effect

      assert [%{name: "Mara", give: "lighthouse"}, %{name: "Jacob", give: "candle"}] =
               request.gives

      assert request.count == 2
      assert Game.view(state, nil).phase == :writing
    end

    test "page_written sets the Page and moves phase to bridging", %{state: state} do
      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      meta = %{
        model: "gemini-3.8-flash",
        arm: :flash,
        prompt_version: "author-3",
        cost_usd: 0.001,
        latency_ms: 250,
        why: "Distant worlds."
      }

      event = {:page_written, %{bookends: ["cliff", "wax"], meta: meta}}

      assert {:ok, state, []} = Game.apply(state, event)

      view = Game.view(state, "seat-Mara")
      assert view.phase == :bridging
      assert view.bookends == ["cliff", "wax"]
      assert view.attempt == %{number: 1, of: Game.attempt_cap()}

      # A duplicate page_written is ignored
      assert {:ok, ^state, []} = Game.apply(state, event)
    end

    test "author_failed records failure and keeps phase in writing", %{state: state} do
      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      assert {:ok, failed_state, []} =
               Game.apply(state, {:author_failed, %{reason: "timed out"}})

      assert Game.view(failed_state, nil).phase == :writing
      assert Game.view(failed_state, nil).author_failure == "timed out"

      # Either Seat may retry
      assert {:ok, _retried_by_jacob, [{:author, _}]} =
               Game.apply(failed_state, {:author_retried, %{seat_id: "seat-Jacob"}})

      # Retrying clears failure and owes author effect again
      assert {:ok, retried_state, [{:author, _}]} =
               Game.apply(failed_state, {:author_retried, %{seat_id: "seat-Mara"}})

      assert Game.view(retried_state, nil).author_failure == nil

      # Either Seat may reset gives
      assert {:ok, reset_by_jacob, []} =
               Game.apply(failed_state, {:gives_reset, %{seat_id: "seat-Jacob"}})

      assert Game.view(reset_by_jacob, nil).phase == :giving

      # Resetting gives clears every Give and returns to giving
      assert {:ok, reset_state, []} =
               Game.apply(failed_state, {:gives_reset, %{seat_id: "seat-Mara"}})

      assert Game.view(reset_state, nil).phase == :giving
      assert Game.view(reset_state, nil).gives_in == 0

      # Errors when not failed, unseated, or in wrong phase
      assert {:error, :not_failed} =
               Game.apply(state, {:author_retried, %{seat_id: "seat-Mara"}})

      assert {:error, :no_such_seat} =
               Game.apply(failed_state, {:author_retried, %{seat_id: "seat-Stranger"}})

      assert {:error, :no_such_seat} =
               Game.apply(failed_state, {:gives_reset, %{seat_id: "seat-Stranger"}})

      assert {:error, :not_writing} =
               Game.apply(reset_state, {:author_failed, %{reason: "error"}})
    end

    test "next_page clears Page and returns to giving, remembering last Give for prefill" do
      # Start with a closed page that had gives
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      meta = %{
        model: "gemini-3.8-flash",
        arm: :flash,
        prompt_version: "author-3",
        cost_usd: 0.001,
        latency_ms: 250,
        why: "why"
      }

      {:ok, state, _} =
        Game.apply(state, {:page_written, %{bookends: ["cliff", "wax"], meta: meta}})

      # Commit bridges and grade with a meld (91) to close the page
      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Mara", bridge: "cairn"}})

      {:ok, state, effects} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "cairo"}})

      [{:assay, _}] = Enum.filter(effects, &match?({:assay, _}, &1))

      {:ok, closed_state, _} =
        Game.apply(
          state,
          {:verdict_received,
           %{closeness: 91, reasoning: "r", quip: "q", furthest: ["cairn", "cairo"], meta: %{}}}
        )

      assert Game.view(closed_state, nil).phase == :closed

      assert {:ok, next_state, []} =
               Game.apply(closed_state, {:next_page, %{seat_id: "seat-Mara"}})

      view_m = Game.view(next_state, "seat-Mara")
      view_j = Game.view(next_state, "seat-Jacob")

      assert view_m.phase == :giving
      assert view_m.bookends == nil
      assert view_m.your_give == nil
      assert view_m.your_last_give == "lighthouse"
      assert view_m.gives_in == 0

      assert view_j.your_give == nil
      assert view_j.your_last_give == "candle"
    end
  end

  describe "the Author writes one Bookend per Give at a Full table (ticket 03, #120)" do
    @six ~w(Mara Jacob Ada Ida Ola Ora)
    @eight ~w(Mara Jacob Ada Ida Ola Ora Ivy Ned)

    defp six_table(opts \\ []) do
      Game.init(
        Keyword.merge(
          [seat_limit: 6, seats: Enum.map(@six, &seat/1)],
          opts
        )
      )
    end

    defp eight_table(opts \\ []) do
      Game.init(
        Keyword.merge(
          [seat_limit: 8, seats: Enum.map(@eight, &seat/1)],
          opts
        )
      )
    end

    defp give_all(state, names \\ @six) do
      Enum.reduce(names, {state, []}, fn name, {state, _effects} ->
        {:ok, state, effects} =
          Game.apply(
            state,
            {:give_committed, %{seat_id: "seat-" <> name, give: "setting #{name}"}}
          )

        {state, effects}
      end)
    end

    test "a six-Seat Full table asks for six Bookends, one per Give" do
      {state, effects} = give_all(six_table())
      assert [{:author, request}] = effects
      assert request.count == 6
      assert Enum.map(request.gives, & &1.name) == @six

      six_bookends = ~w(lantern harbour summit ember grove spire)

      assert {:ok, bridging, []} =
               Game.apply(state, {:page_written, %{bookends: six_bookends}})

      view = Game.view(bridging, nil)
      assert view.phase == :bridging
      assert view.bookends == six_bookends
      assert view.full_table == true
    end

    test "Full table off asks for two Bookends from two different Gives" do
      {state, effects} = give_all(six_table(full_table: false))
      assert [{:author, request}] = effects
      assert request.count == 2
      assert length(request.gives) == 6

      assert {:ok, bridging, []} =
               Game.apply(state, {:page_written, %{bookends: ["lantern", "harbour"]}})

      view = Game.view(bridging, nil)
      assert view.bookends == ["lantern", "harbour"]
      assert view.full_table == false
    end

    test "an eight-Seat Full table asks for eight Bookends, one per Give" do
      {state, effects} = give_all(eight_table(), @eight)
      assert [{:author, request}] = effects
      assert request.count == 8
      assert Enum.map(request.gives, & &1.name) == @eight

      eight_bookends = ~w(lantern harbour summit ember grove spire ridge hearth)

      assert {:ok, bridging, []} =
               Game.apply(state, {:page_written, %{bookends: eight_bookends}})

      view = Game.view(bridging, nil)
      assert view.phase == :bridging
      assert view.bookends == eight_bookends
      assert view.full_table == true
    end

    test "eight Seats with Full table off still ask for two Bookends" do
      {_state, effects} = give_all(eight_table(full_table: false), @eight)
      assert [{:author, request}] = effects
      assert request.count == 2
      assert length(request.gives) == 8
    end

    test "setting the Room's Full table rule off asks the next Page for two Bookends" do
      {_state, effects} = give_all(Game.set_full_table(six_table(), false))
      assert [{:author, request}] = effects
      assert request.count == 2
    end

    test "eight Seats have eight distinct house colours" do
      state = eight_table()
      colours = Enum.map(state.seats, &Game.seat_colour(state, &1))
      assert length(colours) == 8
      assert colours == Enum.uniq(colours)
    end
  end

  describe "the Room starts when everyone is here (ticket 08)" do
    test "a Page starts when the Seats present declare their Gives are in rather than waiting for Room to fill" do
      state =
        Game.init(
          seat_limit: 6,
          seats: [seat("Mara"), seat("Jacob"), seat("Ada"), seat("Bram")]
        )

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      # Fewer than 2 gives: cannot start
      assert {:error, :not_enough_gives} =
               Game.apply(state, {:start_page, %{seat_id: "seat-Mara"}})

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Ada", give: "beacon"}})

      # Bram has not submitted a give yet. Seats present declare their gives are all in:
      assert {:ok, writing_state, [{:author, request}]} =
               Game.apply(state, {:start_page, %{seat_id: "seat-Mara"}})

      assert length(request.gives) == 3
      assert request.count == 3
      assert Enum.map(request.gives, & &1.name) == ["Mara", "Jacob", "Ada"]
      assert Game.view(writing_state, nil).phase == :writing

      # Page is written
      {:ok, bridging_state, []} =
        Game.apply(writing_state, {:page_written, %{bookends: ["ocean", "lantern"]}})

      assert Game.view(bridging_state, nil).phase == :bridging

      # Only the 3 seats that gave settings are bridging
      {:ok, s1, []} =
        Game.apply(
          bridging_state,
          {:bridge_committed, %{seat_id: "seat-Mara", bridge: "coast"}}
        )

      {:ok, s2, []} =
        Game.apply(s1, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "harbour"}})

      # The 3rd bridge from Ada triggers assaying without waiting for Bram
      assert {:ok, assaying_state, effects} =
               Game.apply(s2, {:bridge_committed, %{seat_id: "seat-Ada", bridge: "shore"}})

      assert Game.view(assaying_state, nil).phase == :assaying
      assert [:beat, {:assay, assay_req}] = effects
      assert assay_req.bridges == ["coast", "harbour", "shore"]
    end

    test "a late Seat joining after the Page started watches this Page and plays on next Page" do
      state =
        Game.init(
          seat_limit: 6,
          seats: [seat("Mara"), seat("Jacob")]
        )

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      {:ok, writing_state, [{:author, _}]} =
        Game.apply(state, {:start_page, %{seat_id: "seat-Jacob"}})

      {:ok, bridging_state, []} =
        Game.apply(writing_state, {:page_written, %{bookends: ["ocean", "lantern"]}})

      # A late Seat arrives
      {:ok, with_late, []} = Game.apply(bridging_state, {:seat_joined, seat("Ada")})

      late_view = Game.view(with_late, "seat-Ada")
      active_view = Game.view(with_late, "seat-Mara")

      assert late_view.late? == true
      assert active_view.late? == false

      # Late seat cannot commit bridge for this attempt
      assert {:error, :not_playing_page} =
               Game.apply(with_late, {:bridge_committed, %{seat_id: "seat-Ada", bridge: "shore"}})

      # Mara and Jacob commit and reveal with non-meld verdict
      {:ok, s1, []} =
        Game.apply(with_late, {:bridge_committed, %{seat_id: "seat-Mara", bridge: "coast"}})

      {:ok, s2, _} =
        Game.apply(s1, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "harbour"}})

      {:ok, reveal_state, _} =
        Game.apply(
          s2,
          {:verdict_received,
           %{
             closeness: 70,
             reasoning: "close",
             quip: "quip",
             furthest: ["coast", "harbour"],
             meta: %{}
           }}
        )

      assert Game.view(reveal_state, nil).phase == :reveal
      # Spectator gives are not included in reveal
      refute Enum.any?(Game.view(reveal_state, nil).reveal.gives, &(&1.seat_id == "seat-Ada"))

      # Late seat cannot advance attempt
      assert {:error, :not_playing_page} =
               Game.apply(reveal_state, {:attempt_advanced, %{seat_id: "seat-Ada"}})

      # Mara advances attempt
      {:ok, attempt2_state, []} =
        Game.apply(reveal_state, {:attempt_advanced, %{seat_id: "seat-Mara"}})

      # Ada is still late in attempt 2
      assert Game.view(attempt2_state, "seat-Ada").late? == true

      # Attempt 2: Mara and Jacob commit bridges and meld
      {:ok, a2_s1, []} =
        Game.apply(
          attempt2_state,
          {:bridge_committed, %{seat_id: "seat-Mara", bridge: "beacon"}}
        )

      {:ok, a2_s2, _} =
        Game.apply(a2_s1, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "beacon"}})

      {:ok, closed_state, _} =
        Game.apply(
          a2_s2,
          {:verdict_received,
           %{
             closeness: 90,
             reasoning: "meld",
             quip: "quip",
             furthest: ["beacon", "beacon"],
             meta: %{}
           }}
        )

      assert Game.view(closed_state, nil).phase == :closed

      # Starting next page includes Ada
      {:ok, next_page_state, []} =
        Game.apply(closed_state, {:next_page, %{seat_id: "seat-Ada"}})

      ada_next_view = Game.view(next_page_state, "seat-Ada")
      assert ada_next_view.phase == :giving
      assert ada_next_view.late? == false

      # Ada can now give
      assert {:ok, _, []} =
               Game.apply(
                 next_page_state,
                 {:give_committed, %{seat_id: "seat-Ada", give: "starlight"}}
               )
    end

    test "validates start_page: seat must exist and phase must be giving" do
      state =
        Game.init(
          seat_limit: 6,
          seats: [seat("Mara"), seat("Jacob")]
        )

      assert {:error, :no_such_seat} =
               Game.apply(state, {:start_page, %{seat_id: "seat-Ghost"}})

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      # A third seat arrives but hasn't entered a give; cannot start page
      {:ok, with_third, []} = Game.apply(state, {:seat_joined, seat("Ada")})

      assert {:error, :give_required} =
               Game.apply(with_third, {:start_page, %{seat_id: "seat-Ada"}})

      {:ok, writing_state, [{:author, _}]} =
        Game.apply(state, {:start_page, %{seat_id: "seat-Jacob"}})

      # Once writing, cannot call start_page again
      assert {:error, :not_giving} =
               Game.apply(writing_state, {:start_page, %{seat_id: "seat-Mara"}})
    end

    test "late seat cannot propose or agree to overrule, only active seats are needed for unanimity" do
      state =
        Game.init(
          seat_limit: 6,
          seats: [seat("Mara"), seat("Jacob")]
        )

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      {:ok, writing_state, [{:author, _}]} =
        Game.apply(state, {:start_page, %{seat_id: "seat-Jacob"}})

      {:ok, bridging_state, []} =
        Game.apply(writing_state, {:page_written, %{bookends: ["ocean", "lantern"]}})

      {:ok, with_late, []} = Game.apply(bridging_state, {:seat_joined, seat("Ada")})

      {:ok, s1, []} =
        Game.apply(with_late, {:bridge_committed, %{seat_id: "seat-Mara", bridge: "coast"}})

      {:ok, s2, _} =
        Game.apply(s1, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "harbour"}})

      {:ok, reveal_state, _} =
        Game.apply(
          s2,
          {:verdict_received,
           %{
             closeness: 75,
             reasoning: "close",
             quip: "quip",
             furthest: ["coast", "harbour"],
             meta: %{}
           }}
        )

      # Late seat Ada cannot propose overrule
      assert {:error, :not_playing_page} =
               Game.apply(reveal_state, {:overrule_proposed, %{seat_id: "seat-Ada"}})

      # Mara proposes
      {:ok, prop_state, []} =
        Game.apply(reveal_state, {:overrule_proposed, %{seat_id: "seat-Mara"}})

      # Ada cannot agree
      assert {:error, :not_playing_page} =
               Game.apply(prop_state, {:overrule_agreed, %{seat_id: "seat-Ada"}})

      # When Jacob agrees, unanimity of the 2 active seats is satisfied
      assert {:ok, overruled_state, [_overrule_effect, _chronicle_effect]} =
               Game.apply(prop_state, {:overrule_agreed, %{seat_id: "seat-Jacob"}})

      assert Game.view(overruled_state, nil).reveal.closeness == 90
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

    test "phrases, digits, hyphens and apostrophes are legal bridges and 'Viking beaches' commits" do
      {:ok, state, []} = commit(bridging(), "Mara", "Viking beaches")
      assert Game.view(state, "seat-Mara").your_bridge == "viking beaches"

      {:ok, state2, []} = commit(bridging(), "Mara", "ice-cream")
      assert Game.view(state2, "seat-Mara").your_bridge == "ice-cream"

      {:ok, state3, []} = commit(bridging(), "Mara", "rock 'n' roll")
      assert Game.view(state3, "seat-Mara").your_bridge == "rock 'n' roll"

      {:ok, state4, []} = commit(bridging(), "Mara", "apollo 11")
      assert Game.view(state4, "seat-Mara").your_bridge == "apollo 11"
    end

    test "a Bridge sharing root with bookend is refused" do
      assert {:error, {:illegal_bridge, "\"lanterns\" shares a root with \"lantern\"."}} =
               commit(bridging(), "Mara", "lanterns")

      assert {:error, {:illegal_bridge, "\"lantern\" shares a root with \"lantern\"."}} =
               commit(bridging(), "Mara", "lantern")
    end

    test "in attempt 2, carried bridges and earlier attempt bridges are barred" do
      # Attempt 1: bookends are ["lantern", "harbour"].
      # Mara bridges "cairn", Jacob bridges "beacon".
      # They do not meld (closeness 0).
      {revealed, _effects} = attempt(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}], 0)

      # Advance to attempt 2: carried bookends are ["cairn", "beacon"]
      attempt2 = again(revealed)

      view = Game.view(attempt2, nil)
      assert view.attempt.number == 2
      assert view.bookends == ["cairn", "beacon"]
      assert Game.barred_words(attempt2) == ["cairn", "beacon", "lantern", "harbour"]
      assert Game.view(attempt2, nil).barred_words == ["cairn", "beacon", "lantern", "harbour"]

      # Carried bridge is barred as bookend
      assert {:error, {:illegal_bridge, "\"cairn\" shares a root with \"cairn\"."}} =
               commit(attempt2, "Mara", "cairn")

      # Attempt 1's bookends are also barred
      assert {:error, {:illegal_bridge, "\"lantern\" shares a root with \"lantern\"."}} =
               commit(attempt2, "Mara", "lantern")

      # "lava rock" after "lava" refused naming lava:
      # If attempt 1 had "lava", in attempt 2 "lava rock" is refused naming lava
      lava_page = %{@page | bookends: ["mountain", "sea"]}

      lava_bridging =
        Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")], page: lava_page)

      {revealed_lava, _effects} =
        attempt(lava_bridging, [{"Mara", "lava"}, {"Jacob", "island"}], 0)

      attempt2_lava = again(revealed_lava)

      assert {:error, {:illegal_bridge, "\"lava rock\" shares a root with \"lava\"."}} =
               commit(attempt2_lava, "Mara", "lava rock")
    end
  end

  describe "the last commit" do
    test "asks for exactly one assay and starts the beat" do
      {state, effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])

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

      state = grade(state, effects, 60)

      for viewer <- ["seat-Mara", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :reveal

        assert Enum.map(view.reveal.bridges, &{&1.name, &1.bridge}) == [
                 {"Mara", "cairn"},
                 {"Jacob", "beacon"}
               ]
      end
    end

    test "carries the closeness and the band, but no reasoning" do
      view = Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], 92), nil)

      assert view.reveal.closeness == 92
      assert view.reveal.band == :meld
      assert view.reveal.melded? == true
      assert view.reveal.graded? == true
      refute Map.has_key?(view.reveal, :reasoning)
    end

    test "the meld threshold is where a Meld starts and one under it is not one" do
      threshold = Thereish.Ladder.meld_threshold()

      assert Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], threshold), nil).reveal.melded?

      refute Game.view(
               revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], threshold - 1),
               nil
             ).reveal.melded?
    end

    test "each band is read at its own floor" do
      for {band, floor} <- Thereish.Ladder.bands() do
        view = Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], floor), nil)

        assert view.reveal.band == band
      end
    end

    test "a closeness off the scale is brought back onto it" do
      assert Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], 140), nil).reveal.closeness ==
               100

      assert Game.view(revealed([{"Mara", "cairn"}, {"Jacob", "beacon"}], -20), nil).reveal.closeness ==
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
               {"Mara", "cairn"},
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
      melded = grade(ctx.ungraded, ctx.effects, Thereish.Ladder.meld_threshold())

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
      assert Enum.map(reveal.furthest, & &1.name) == ["Mara", "Ada"]
    end

    test "the reveal waits for the Verdict", ctx do
      assert Game.view(ctx.ungraded, nil).phase == :assaying
      assert Game.view(ctx.ungraded, nil).reveal == nil
    end
  end

  describe "a verdict that never comes" do
    test "the Page still reveals, with no number and no Meld" do
      {state, _effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])

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
      {state, _effects} = attempt(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}], 10)

      assert Game.view(state, nil).next_bookends == ["cairn", "beacon"]

      state = again(state)

      for viewer <- ["seat-Mara", "seat-Jacob", nil] do
        view = Game.view(state, viewer)

        assert view.phase == :bridging
        assert view.bookends == ["cairn", "beacon"]
        assert view.attempt == %{number: 2, of: Game.attempt_cap()}
        assert view.reveal == nil
        assert view.your_bridge == nil
        assert Enum.map(view.seats, & &1.committed?) == [false, false]
      end
    end

    test "each earlier Attempt in the assay request carries its Quip, or nil without one" do
      {state, effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      [{:assay, request}] = assays(effects)

      assert request.earlier_attempts == []

      verdict = %{
        closeness: 10,
        reasoning: "because",
        quip: "A cairn walks into a lighthouse.",
        furthest: request.bridges,
        meta: %{}
      }

      {:ok, state, _effects} = Game.apply(state, {:verdict_received, verdict})

      {state, effects} =
        commit_all(again(state), [{"Mara", "stone"}, {"Jacob", "signal"}])

      [{:assay, request}] = assays(effects)
      assert [%{number: 1, quip: "A cairn walks into a lighthouse."}] = request.earlier_attempts

      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{}})

      {_state, effects} =
        commit_all(again(state), [{"Mara", "granite"}, {"Jacob", "flare"}])

      [{:assay, request}] = assays(effects)

      assert Enum.map(request.earlier_attempts, &{&1.number, &1.quip}) == [
               {1, "A cairn walks into a lighthouse."},
               {2, nil}
             ]
    end

    test "the Page keeps the Bookends it was authored with" do
      {state, _effects} = attempt(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}], 10)

      assert again(state).page.bookends == ["lantern", "harbour"]
    end

    test "the attempt that was played is kept, so the arc can be read at the end" do
      {state, _effects} = attempt(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}], 10)

      assert [first] = Game.view(again(state), nil).played
      assert first.number == 1
      assert first.bookends == ["lantern", "harbour"]
      assert Enum.map(first.bridges, & &1.bridge) == ["cairn", "beacon"]
      assert first.closeness == 10
      assert first.band == :miss
    end

    test "at four Seats it is the two the Assayer named, whoever wrote them" do
      {state, effects} = four_committed_two()
      state = grade(state, effects, 30, ["beacon", "signal"])

      # The Assayer read four words together and said these two are the ends of
      # the table. Nothing here recomputes that.
      assert Game.view(state, nil).next_bookends == ["beacon", "signal"]
      assert Game.view(state, nil).next_bookends_chosen? == true
      assert Game.view(again(state), nil).bookends == ["beacon", "signal"]
    end

    test "with no Verdict the first two in roster order carry, and the view says so" do
      {state, _effects} = four_committed_two()
      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{}})

      assert Game.view(state, nil).next_bookends == ["cairn", "beacon"]
      assert Game.view(state, nil).next_bookends_chosen? == false
      assert Game.view(again(state), nil).bookends == ["cairn", "beacon"]
    end

    test "a word nobody wrote is no choice: the roster carries, and the view says so" do
      {state, effects} = four_committed_two()
      state = grade(state, effects, 30, ["beacon", "lighthouse"])

      # "lighthouse" is a paraphrase of nobody's Bridge. Sending the table to an
      # Bookend none of them wrote would be a Page they were never asked to play.
      assert Game.view(state, nil).next_bookends == ["cairn", "beacon"]
      assert Game.view(state, nil).next_bookends_chosen? == false
      assert Game.view(state, nil).reveal.furthest == nil
    end

    test "a Page nobody could grade at all still carries something forward" do
      {state, _effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{}})

      assert Game.view(state, nil).next_bookends == ["cairn", "beacon"]
      assert Game.view(again(state), nil).bookends == ["cairn", "beacon"]
    end

    test "there is nothing to carry forward before the reveal" do
      state = bridging()

      assert Game.view(state, nil).next_bookends == nil

      assert {:error, :not_revealed} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Mara"}})

      {:ok, state, []} = commit(state, "Mara", "cairn")

      assert {:error, :not_revealed} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Mara"}})
    end

    test "only a Seat in this Room may start the next attempt" do
      {state, _effects} = attempt(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}], 10)

      assert {:error, :no_such_seat} =
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Ada"}})
    end
  end

  describe "a Page closes" do
    test "the moment a Meld lands, however many attempts were left" do
      {state, _effects} = attempt(bridging(), [{"Mara", "cairn"}, {"Jacob", "cairo"}], 90)

      for viewer <- ["seat-Mara", "seat-Jacob", nil] do
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
               Game.apply(state, {:attempt_advanced, %{seat_id: "seat-Mara"}})

      assert {:error, :not_bridging} = commit(state, "Mara", "cairn")
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
      {state, _effects} = attempt(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}], 10)

      {_state, effects} =
        attempt(again(state), [{"Mara", "wharf"}, {"Jacob", "wharfinger"}], 92)

      assert [{:chronicle, %Entry{} = entry}] = chronicles(effects)
      assert entry.page == @page
      assert entry.closed_because == :meld
      assert entry.melded? == true
      assert entry.closeness == 92

      assert [first, second] = entry.attempts
      assert first.number == 1
      assert first.bookends == ["lantern", "harbour"]

      assert first.bridges == [
               %{seat_id: "seat-Mara", bridge: "cairn"},
               %{seat_id: "seat-Jacob", bridge: "beacon"}
             ]

      assert first.closeness == 10
      assert first.melded? == false

      assert second.bookends == ["cairn", "beacon"]
      assert second.melded? == true

      assert [verdict] = second.verdicts
      assert verdict.bridges == ["wharf", "wharfinger"]
      assert verdict.furthest == ["wharf", "wharfinger"]
      assert verdict.seat_ids == ["seat-Mara", "seat-Jacob"]
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
      {state, _effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      state = again(elem(Game.apply(state, {:verdict_unavailable, %{}}), 1))

      {_state, effects} = attempt(state, [{"Mara", "wharf"}, {"Jacob", "wharfinger"}], 92)

      assert [{:chronicle, entry}] = chronicles(effects)
      assert [first, _second] = entry.attempts
      assert [verdict] = first.verdicts
      assert verdict.graded? == false
      assert verdict.closeness == nil
      assert verdict.furthest == nil
      assert verdict.bridges == ["cairn", "beacon"]
    end

    test "and nothing is owed while the Page is still open" do
      {_state, effects} = attempt(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}], 10)

      assert chronicles(effects) == []
    end
  end

  describe "a verdict is a ruling, not a suggestion" do
    test "the grade that landed first is the grade that stands" do
      {state, effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      graded = grade(state, effects, 78)

      second_thought =
        {:verdict_received, %{closeness: 12, reasoning: "on reflection", furthest: []}}

      assert {:ok, ^graded, []} = Game.apply(graded, second_thought)
      assert Game.view(graded, nil).reveal.closeness == 78
    end

    test "a verdict for an attempt the Page has moved on from is refused" do
      {state, effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      moved_on = again(grade(state, effects, 10))

      late = {:verdict_received, %{closeness: 90, reasoning: "at last", furthest: []}}

      assert {:error, :no_verdict_expected} = Game.apply(moved_on, late)
    end

    test "a verdict for a Page whose Bridges are not all in is refused" do
      {:ok, state, []} = commit(bridging(), "Mara", "cairn")

      event = {:verdict_received, %{closeness: 90, reasoning: "", furthest: []}}

      assert {:error, :no_verdict_expected} = Game.apply(state, event)
    end
  end

  describe "overruling a grade" do
    setup do
      {state, effects} = commit_all(bridging(), [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      %{revealed: grade(state, effects, 41)}
    end

    test "any Seat can propose an overrule from the reveal", ctx do
      assert {:ok, state, []} =
               Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Mara"}})

      # The proposal is pending, and the grade is untouched
      assert Game.view(state, nil).reveal.closeness == 41

      mara_view = Game.view(state, "seat-Mara")
      assert mara_view.overrule.pending?
      assert mara_view.overrule.proposer_id == "seat-Mara"
      assert mara_view.overrule.proposer_name == "Mara"
      assert mara_view.overrule.you_proposed?
      assert mara_view.overrule.you_agreed?

      jacob_view = Game.view(state, "seat-Jacob")
      assert jacob_view.overrule.pending?
      assert jacob_view.overrule.proposer_id == "seat-Mara"
      refute jacob_view.overrule.you_proposed?
      refute jacob_view.overrule.you_agreed?

      stage_view = Game.view(state, nil)
      assert stage_view.overrule.pending?
      assert stage_view.overrule.proposer_name == "Mara"
      refute stage_view.overrule.you_proposed?
      refute stage_view.overrule.you_agreed?
    end

    test "a proposed overrule defaults to the meld floor read from the Ladder, not 100", ctx do
      {:ok, proposed, []} =
        Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Mara"}})

      view = Game.view(proposed, "seat-Mara")
      assert view.overrule.closeness == Ladder.meld_threshold()
      assert view.overrule.closeness == 90
    end

    test "cannot propose an overrule before the reveal" do
      state = bridging()

      assert {:error, :not_revealed} =
               Game.apply(state, {:overrule_proposed, %{seat_id: "seat-Mara"}})
    end

    test "someone not in the Room cannot propose an overrule", ctx do
      assert {:error, :no_such_seat} =
               Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Ada"}})
    end

    test "an overrule takes effect only when every Seat agrees (unanimity)", ctx do
      {:ok, proposed, []} =
        Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Mara"}})

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
      assert overrule.proposer_seat_id == "seat-Mara"
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
        Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Mara"}})

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
               Game.apply(revealed, {:overrule_proposed, %{seat_id: "seat-Mara"}})

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
        Game.apply(revealed, {:overrule_proposed, %{seat_id: "seat-Mara"}})

      assert {:ok, declined, []} =
               Game.apply(proposed, {:overrule_declined, %{seat_id: "seat-Ida"}})

      assert Game.view(declined, nil).overrule == nil
      assert Game.view(declined, nil).reveal.closeness == 30
    end

    test "the proposal expires cleanly if the Page moves on", ctx do
      {:ok, proposed, []} =
        Game.apply(ctx.revealed, {:overrule_proposed, %{seat_id: "seat-Mara"}})

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
        commit_all(bridging(), [{"Mara", "dock"}, {"Jacob", "wharf"}])

      revealed = grade(state, effects, 62)
      %{revealed: revealed}
    end

    test "tapping fair at the reveal emits a fairness_tap effect with all required fields", ctx do
      assert {:ok, tapped, effects} =
               Game.apply(
                 ctx.revealed,
                 {:fairness_tapped, %{seat_id: "seat-Mara", label: "fair"}}
               )

      assert [
               {:fairness_tap,
                %{
                  seat_id: "seat-Mara",
                  attempt_number: 1,
                  bookends: ["lantern", "harbour"],
                  bridges: ["dock", "wharf"],
                  closeness: 62,
                  band: "close",
                  model: "test",
                  prompt_version: "v1",
                  label: "fair"
                }}
             ] = effects

      assert Game.view(tapped, "seat-Mara").your_tap == "fair"
      assert Game.view(tapped, "seat-Jacob").your_tap == nil
    end

    test "two seats can disagree about the same grade and both persist", ctx do
      assert {:ok, s1, [fair_effect]} =
               Game.apply(
                 ctx.revealed,
                 {:fairness_tapped, %{seat_id: "seat-Mara", label: "fair"}}
               )

      assert {:ok, s2, [harsh_effect]} =
               Game.apply(s1, {:fairness_tapped, %{seat_id: "seat-Jacob", label: "too_harsh"}})

      assert match?({:fairness_tap, %{seat_id: "seat-Mara", label: "fair"}}, fair_effect)
      assert match?({:fairness_tap, %{seat_id: "seat-Jacob", label: "too_harsh"}}, harsh_effect)

      assert Game.view(s2, "seat-Mara").your_tap == "fair"
      assert Game.view(s2, "seat-Jacob").your_tap == "too_harsh"
    end

    test "tapping never blocks or delays the next attempt", ctx do
      {:ok, tapped, _} =
        Game.apply(
          ctx.revealed,
          {:fairness_tapped, %{seat_id: "seat-Mara", label: "too_kind"}}
        )

      assert {:ok, advanced, []} =
               Game.apply(tapped, {:attempt_advanced, %{seat_id: "seat-Jacob"}})

      view = Game.view(advanced, "seat-Mara")
      assert view.attempt.number == 2
      assert view.phase == :bridging
      assert view.your_tap == nil
    end

    test "skipping the tap is normal: attempt advances without any tap", ctx do
      assert {:ok, advanced, []} =
               Game.apply(ctx.revealed, {:attempt_advanced, %{seat_id: "seat-Jacob"}})

      assert Game.view(advanced, "seat-Mara").attempt.number == 2
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
      assert tap.closeness == 45
      assert tap.label == "too_harsh"
    end

    test "cannot tap when not revealed" do
      state = bridging()

      assert {:error, :not_revealed} =
               Game.apply(state, {:fairness_tapped, %{seat_id: "seat-Mara", label: "fair"}})
    end
  end

  describe "the bookends tap (ticket 08)" do
    setup do
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "beach walk"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "old tower"}})

      meta = %{
        model: "gemini-3.8-flash",
        arm: :flash,
        prompt_version: "author-3",
        cost_usd: 0.001,
        latency_ms: 250,
        why: "Distant worlds."
      }

      {:ok, state, _} =
        Game.apply(state, {:page_written, %{bookends: ["cliff", "wax"], meta: meta}})

      {state, effects} = commit_all(state, [{"Mara", "dock"}, {"Jacob", "wharf"}])
      closed = grade(state, effects, Thereish.Ladder.meld_threshold())

      %{closed: closed}
    end

    test "tapping bookends at the close emits a bookends_tap effect carrying bookends, gives, author meta and arm",
         ctx do
      assert Game.view(ctx.closed, nil).phase == :closed

      assert {:ok, tapped, effects} =
               Game.apply(
                 ctx.closed,
                 {:bookends_tapped, %{seat_id: "seat-Mara", label: "great"}}
               )

      assert [
               {:bookends_tap,
                %{
                  seat_id: "seat-Mara",
                  label: "great",
                  bookends: ["cliff", "wax"],
                  gives: %{"seat-Mara" => "beach walk", "seat-Jacob" => "old tower"},
                  author_meta: %{
                    model: "gemini-3.8-flash",
                    arm: :flash,
                    prompt_version: "author-3",
                    cost_usd: 0.001,
                    latency_ms: 250,
                    why: "Distant worlds."
                  },
                  arm: :flash
                } = tap}
             ] = effects

      # Which Chronicle Page it is on is the Room's to say.
      refute Map.has_key?(tap, :page_id)
      refute Map.has_key?(tap, :page_identifier)

      assert Game.view(tapped, "seat-Mara").your_bookends_tap == "great"
      assert Game.view(tapped, "seat-Mara").bookends_taps == %{"seat-Mara" => "great"}
      assert Game.view(tapped, "seat-Jacob").your_bookends_tap == nil
    end

    test "bookends tap is replaceable per seat", ctx do
      assert {:ok, s1, _} =
               Game.apply(
                 ctx.closed,
                 {:bookends_tapped, %{seat_id: "seat-Mara", label: "fine"}}
               )

      assert {:ok, s2, [{:bookends_tap, tap2}]} =
               Game.apply(
                 s1,
                 {:bookends_tapped, %{seat_id: "seat-Mara", label: "great"}}
               )

      assert tap2.label == "great"
      assert Game.view(s2, "seat-Mara").your_bookends_tap == "great"
      assert Game.view(s2, "seat-Mara").bookends_taps == %{"seat-Mara" => "great"}
    end

    test "rejects tapping when phase is not :closed" do
      open_state = bridging()

      assert {:error, :not_closed} =
               Game.apply(
                 open_state,
                 {:bookends_tapped, %{seat_id: "seat-Mara", label: "great"}}
               )
    end

    test "rejects an invalid bookends tap label", ctx do
      assert {:error, :invalid_label} =
               Game.apply(
                 ctx.closed,
                 {:bookends_tapped, %{seat_id: "seat-Mara", label: "bogus"}}
               )
    end

    test "rejects unknown seat", ctx do
      assert {:error, :no_such_seat} =
               Game.apply(
                 ctx.closed,
                 {:bookends_tapped, %{seat_id: "seat-Ghost", label: "great"}}
               )
    end

    test "next_page clears bookends_taps", ctx do
      {:ok, tapped, _} =
        Game.apply(
          ctx.closed,
          {:bookends_tapped, %{seat_id: "seat-Mara", label: "great"}}
        )

      assert {:ok, next_state, []} =
               Game.apply(tapped, {:next_page, %{seat_id: "seat-Mara"}})

      view = Game.view(next_state, "seat-Mara")
      assert view.your_bookends_tap == nil
      assert view.bookends_taps == %{}
    end
  end

  describe "the end screen tells every Give (ticket 09)" do
    test "after the first reveal, every Give is shown with its Seat" do
      state =
        Game.init(
          seat_limit: 2,
          seats: [seat("Mara"), seat("Jacob")]
        )

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      {:ok, state, _} =
        Game.apply(state, {:page_written, %{bookends: ["cliff", "wax"]}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Mara", bridge: "cairn"}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "beacon"}})

      {:ok, reveal_state, _} =
        Game.apply(
          state,
          {:verdict_received,
           %{
             closeness: 85,
             reasoning: "warm",
             quip: "nice bridge",
             furthest: ["cairn", "beacon"],
             meta: %{}
           }}
        )

      assert Game.phase(reveal_state) == :reveal

      reveal_view = Game.view(reveal_state, "seat-Mara")

      assert [
               %{name: "Mara", seat_id: "seat-Mara", text: "lighthouse"},
               %{name: "Jacob", seat_id: "seat-Jacob", text: "candle"}
             ] = reveal_view.reveal.gives

      assert Game.view(reveal_state, nil).reveal.gives == reveal_view.reveal.gives
    end
  end

  describe "masks drawn and kept (ticket 16)" do
    setup do
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])
      %{state: state}
    end

    test "mask_landed records a Mask on the state and rejects unknown seat", %{state: state} do
      mask = %Mask{url: "/media/masks/mask-1.png", meta: %{prompt: "A small square Mask."}}

      assert {:ok, new_state, []} =
               Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: mask}})

      assert new_state.masks["seat-Mara"] == mask

      assert {:error, :no_such_seat} =
               Game.apply(state, {:mask_landed, %{seat_id: "seat-Ghost", mask: mask}})
    end

    test "before first reveal: giver sees own mask, stage and other seat see face_down", %{
      state: state
    } do
      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      mask = %Mask{url: "/media/masks/mask-mara.png", meta: %{}}

      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: mask}})

      # Giver's view
      mara_view = Game.view(state, "seat-Mara")
      assert mara_view.your_mask == mask
      mara_seat = Enum.find(mara_view.seats, &(&1.id == "seat-Mara"))
      jacob_seat = Enum.find(mara_view.seats, &(&1.id == "seat-Jacob"))
      assert mara_seat.mask == mask
      assert jacob_seat.mask == nil
      assert mara_seat.colour == "#c4a35a"
      assert jacob_seat.colour == "#6b3a2a"

      # Other player's view
      jacob_view = Game.view(state, "seat-Jacob")
      assert jacob_view.your_mask == nil
      mara_seat_from_jacob = Enum.find(jacob_view.seats, &(&1.id == "seat-Mara"))
      assert mara_seat_from_jacob.mask == :face_down

      # Stage view
      stage_view = Game.view(state, nil)
      assert stage_view.your_mask == nil
      mara_seat_from_stage = Enum.find(stage_view.seats, &(&1.id == "seat-Mara"))
      jacob_seat_from_stage = Enum.find(stage_view.seats, &(&1.id == "seat-Jacob"))
      assert mara_seat_from_stage.mask == :face_down
      assert jacob_seat_from_stage.mask == nil
    end

    test "dot stands in when limner fails or refuses", %{state: state} do
      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: :dot}})

      mara_view = Game.view(state, "seat-Mara")
      stage_view = Game.view(state, nil)

      assert mara_view.your_mask == :dot
      assert Enum.find(mara_view.seats, &(&1.id == "seat-Mara")).mask == :dot
      assert Enum.find(stage_view.seats, &(&1.id == "seat-Mara")).mask == :face_down
    end

    test "late mask replaces dot in place", %{state: state} do
      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: :dot}})

      assert Game.view(state, "seat-Mara").your_mask == :dot

      late_mask = %Mask{url: "/media/masks/mask-late.png", meta: %{}}

      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: late_mask}})

      assert Game.view(state, "seat-Mara").your_mask == late_mask

      assert Enum.find(Game.view(state, "seat-Mara").seats, &(&1.id == "seat-Mara")).mask ==
               late_mask
    end

    test "all masks visible to everyone after first reveal", %{state: state} do
      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      mask_m = %Mask{url: "/media/masks/m.png", meta: %{}}
      mask_j = %Mask{url: "/media/masks/j.png", meta: %{}}

      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: mask_m}})

      {:ok, state, []} = Game.apply(state, {:mask_landed, %{seat_id: "seat-Jacob", mask: mask_j}})

      {:ok, state, []} =
        Game.apply(state, {:page_written, %{bookends: ["cliff", "wax"], meta: %{}}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Mara", bridge: "cairn"}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "tallow"}})

      verdict = %{
        closeness: 85,
        reasoning: "Good match",
        quip: "Nice!",
        furthest: ["cairn", "tallow"],
        meta: %{}
      }

      {:ok, reveal_state, _} = Game.apply(state, {:verdict_received, verdict})

      m_view = Game.view(reveal_state, "seat-Mara")
      j_view = Game.view(reveal_state, "seat-Jacob")
      s_view = Game.view(reveal_state, nil)

      assert Enum.find(m_view.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(m_view.seats, &(&1.id == "seat-Jacob")).mask == mask_j

      assert Enum.find(j_view.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(j_view.seats, &(&1.id == "seat-Jacob")).mask == mask_j

      assert Enum.find(s_view.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(s_view.seats, &(&1.id == "seat-Jacob")).mask == mask_j
    end

    test "gives_reset and next_page clear masks", %{state: state} do
      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      mask = %Mask{url: "/media/masks/m.png", meta: %{}}
      {:ok, state, []} = Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: mask}})

      assert state.masks["seat-Mara"] == mask

      # On gives_reset
      {:ok, reset_state, []} = Game.apply(state, {:gives_reset, %{seat_id: "seat-Mara"}})
      assert reset_state.masks == %{}

      # On next_page after close
      {:ok, state, []} =
        Game.apply(state, {:page_written, %{bookends: ["cliff", "wax"], meta: %{}}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Mara", bridge: "cairn"}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "cairn"}})

      verdict = %{
        closeness: 95,
        reasoning: "Meld!",
        quip: "Meld",
        furthest: ["cairn", "cairn"],
        meta: %{}
      }

      {:ok, meld_state, _} = Game.apply(state, {:verdict_received, verdict})
      {:ok, next_state, []} = Game.apply(meld_state, {:next_page, %{seat_id: "seat-Mara"}})
      assert next_state.masks == %{}
    end

    test "chronicle entry includes the masks map and a Give per Seat", %{state: state} do
      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      mask_m = %Mask{url: "/media/masks/m.png", meta: %{}}
      mask_j = %Mask{url: "/media/masks/j.png", meta: %{}}

      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: mask_m}})

      {:ok, state, []} = Game.apply(state, {:mask_landed, %{seat_id: "seat-Jacob", mask: mask_j}})

      {:ok, state, []} =
        Game.apply(state, {:page_written, %{bookends: ["cliff", "wax"], meta: %{}}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Mara", bridge: "cairn"}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "cairn"}})

      verdict = %{
        closeness: 95,
        reasoning: "Meld!",
        quip: "Meld",
        furthest: ["cairn", "cairn"],
        meta: %{}
      }

      {:ok, _meld_state, effects} = Game.apply(state, {:verdict_received, verdict})
      assert {:chronicle, entry} = List.keyfind(effects, :chronicle, 0)
      assert entry.masks["seat-Mara"] == mask_m
      assert entry.masks["seat-Jacob"] == mask_j

      assert entry.gives == [
               %Entry.Give{seat_id: "seat-Mara", text: "lighthouse"},
               %Entry.Give{seat_id: "seat-Jacob", text: "candle"}
             ]
    end

    test "dot visibility matches mask visibility rules before and after reveal", %{state: state} do
      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      {:ok, state, []} = Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: :dot}})

      # Before reveal:
      # Mara sees her own dot
      mara_view = Game.view(state, "seat-Mara")
      assert mara_view.your_mask == :dot
      assert Enum.find(mara_view.seats, &(&1.id == "seat-Mara")).mask == :dot

      # Jacob sees face_down for Mara's mask
      jacob_view = Game.view(state, "seat-Jacob")
      mara_in_jacob_view = Enum.find(jacob_view.seats, &(&1.id == "seat-Mara"))
      assert mara_in_jacob_view.mask == :face_down

      # Stage sees face_down for Mara's mask
      stage_view = Game.view(state, nil)
      mara_in_stage_view = Enum.find(stage_view.seats, &(&1.id == "seat-Mara"))
      assert mara_in_stage_view.mask == :face_down

      # After reveal:
      {:ok, state, []} =
        Game.apply(state, {:page_written, %{bookends: ["cliff", "wax"], meta: %{}}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Mara", bridge: "cairn"}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "cairn"}})

      verdict = %{
        closeness: 95,
        reasoning: "Meld!",
        quip: "Meld",
        furthest: ["cairn", "cairn"],
        meta: %{}
      }

      {:ok, meld_state, _} = Game.apply(state, {:verdict_received, verdict})

      # Everyone sees the dot after reveal
      assert Enum.find(Game.view(meld_state, "seat-Mara").seats, &(&1.id == "seat-Mara")).mask ==
               :dot

      assert Enum.find(Game.view(meld_state, "seat-Jacob").seats, &(&1.id == "seat-Mara")).mask ==
               :dot

      assert Enum.find(Game.view(meld_state, nil).seats, &(&1.id == "seat-Mara")).mask == :dot
    end
  end

  describe "masks on the stage (ticket 17)" do
    setup do
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])
      %{state: state}
    end

    test "before first reveal a Seat sees its own Mask and only face-down cards for others; after it, all Masks",
         %{state: state} do
      # Before any give is committed, no masks or cards
      m_view0 = Game.view(state, "seat-Mara")
      j_view0 = Game.view(state, "seat-Jacob")
      s_view0 = Game.view(state, nil)

      assert Enum.find(m_view0.seats, &(&1.id == "seat-Mara")).mask == nil
      assert Enum.find(m_view0.seats, &(&1.id == "seat-Jacob")).mask == nil
      assert Enum.find(j_view0.seats, &(&1.id == "seat-Mara")).mask == nil
      assert Enum.find(s_view0.seats, &(&1.id == "seat-Mara")).mask == nil

      # Mara commits give
      {:ok, state, []} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      mask_m = %Mask{url: "/media/masks/mask-mara.png", meta: %{}}

      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: mask_m}})

      # Mara sees her own mask; Jacob and Stage see face-down for Mara, nil for Jacob
      m_view1 = Game.view(state, "seat-Mara")
      j_view1 = Game.view(state, "seat-Jacob")
      s_view1 = Game.view(state, nil)

      assert Enum.find(m_view1.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(m_view1.seats, &(&1.id == "seat-Jacob")).mask == nil

      assert Enum.find(j_view1.seats, &(&1.id == "seat-Mara")).mask == :face_down
      assert Enum.find(j_view1.seats, &(&1.id == "seat-Jacob")).mask == nil

      assert Enum.find(s_view1.seats, &(&1.id == "seat-Mara")).mask == :face_down
      assert Enum.find(s_view1.seats, &(&1.id == "seat-Jacob")).mask == nil

      # Jacob commits give
      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      mask_j = %Mask{url: "/media/masks/mask-jacob.png", meta: %{}}

      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Jacob", mask: mask_j}})

      # Page written, now bridging (attempt 1)
      {:ok, state, []} =
        Game.apply(state, {:page_written, %{bookends: ["cliff", "wax"], meta: %{}}})

      assert Game.phase(state) == :bridging

      # Before first reveal: each seat sees own mask and only face-down for others; stage sees only face-down
      m_view2 = Game.view(state, "seat-Mara")
      j_view2 = Game.view(state, "seat-Jacob")
      s_view2 = Game.view(state, nil)

      assert Enum.find(m_view2.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(m_view2.seats, &(&1.id == "seat-Jacob")).mask == :face_down

      assert Enum.find(j_view2.seats, &(&1.id == "seat-Mara")).mask == :face_down
      assert Enum.find(j_view2.seats, &(&1.id == "seat-Jacob")).mask == mask_j

      assert Enum.find(s_view2.seats, &(&1.id == "seat-Mara")).mask == :face_down
      assert Enum.find(s_view2.seats, &(&1.id == "seat-Jacob")).mask == :face_down

      # First attempt bridges and verdict (a miss)
      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Mara", bridge: "cairn"}})

      {:ok, state, _} =
        Game.apply(state, {:bridge_committed, %{seat_id: "seat-Jacob", bridge: "tallow"}})

      verdict = %{
        closeness: 45,
        reasoning: "Distant",
        quip: "Far apart",
        furthest: ["cairn", "tallow"],
        meta: %{}
      }

      {:ok, reveal_state, _} = Game.apply(state, {:verdict_received, verdict})
      assert Game.phase(reveal_state) == :reveal

      # At first reveal: every mask turns over together, all Seats see all Masks
      m_view3 = Game.view(reveal_state, "seat-Mara")
      j_view3 = Game.view(reveal_state, "seat-Jacob")
      s_view3 = Game.view(reveal_state, nil)

      assert Enum.find(m_view3.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(m_view3.seats, &(&1.id == "seat-Jacob")).mask == mask_j

      assert Enum.find(j_view3.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(j_view3.seats, &(&1.id == "seat-Jacob")).mask == mask_j

      assert Enum.find(s_view3.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(s_view3.seats, &(&1.id == "seat-Jacob")).mask == mask_j

      # Continue to attempt 2 (phase is :bridging again, but after first reveal)
      {:ok, attempt2_state, []} =
        Game.apply(reveal_state, {:attempt_advanced, %{seat_id: "seat-Mara"}})

      assert Game.phase(attempt2_state) == :bridging
      assert Game.view(attempt2_state, nil).attempt.number == 2

      # All masks remain visible to everyone on attempt 2
      m_view4 = Game.view(attempt2_state, "seat-Mara")
      j_view4 = Game.view(attempt2_state, "seat-Jacob")
      s_view4 = Game.view(attempt2_state, nil)

      assert Enum.find(m_view4.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(m_view4.seats, &(&1.id == "seat-Jacob")).mask == mask_j

      assert Enum.find(j_view4.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(j_view4.seats, &(&1.id == "seat-Jacob")).mask == mask_j

      assert Enum.find(s_view4.seats, &(&1.id == "seat-Mara")).mask == mask_m
      assert Enum.find(s_view4.seats, &(&1.id == "seat-Jacob")).mask == mask_j
    end
  end

  describe "Full table is the Page's rule (ticket 02, #119)" do
    defp written(state, bookends, full_table \\ :omit) do
      attrs =
        case full_table do
          :omit -> %{bookends: bookends}
          value -> %{bookends: bookends, full_table: value}
        end

      {:ok, state, []} = Game.apply(state, {:page_written, attrs})
      state
    end

    defp giving do
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      state
    end

    test "the Game copies the Room's rule onto the Page and exposes it" do
      state = written(giving(), ["cliff", "wax"], false)

      assert Game.view(state, "seat-Mara").full_table == false
      assert Game.view(state, "seat-Jacob").full_table == false
      assert Game.view(state, nil).full_table == false
    end

    test "a Page written with no rule is a Full table, the default" do
      state = written(giving(), ["cliff", "wax"])

      assert Game.view(state, nil).full_table == true
    end

    test "a Page written under one rule keeps it after the Room flips, and the next Page takes the new one" do
      state = written(giving(), ["cliff", "wax"], true)
      assert Game.view(state, nil).full_table == true

      {state, effects} = commit_all(state, [{"Mara", "cairn"}, {"Jacob", "cairo"}])
      state = grade(state, effects, 91)
      assert Game.view(state, nil).phase == :closed
      assert Game.view(state, nil).full_table == true

      {:ok, state, []} = Game.apply(state, {:next_page, %{seat_id: "seat-Mara"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "ocean"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "lantern"}})

      state = written(state, ["tide", "wick"], false)
      assert Game.view(state, nil).full_table == false
    end
  end

  describe "every Bridge carries forward at a Full table (ticket 05, #122)" do
    @six ~w(Mara Jacob Ada Ida Ola Ora)
    @six_bookends ~w(lantern harbour summit ember grove spire)
    @six_bridges ~w(cairn beacon wharf signal torch lamp)

    defp six_full do
      Game.init(
        seat_limit: 6,
        seats: Enum.map(@six, &seat/1),
        page: %Document{bookends: @six_bookends, full_table: true},
        full_table: true
      )
    end

    defp six_off do
      Game.init(
        seat_limit: 6,
        seats: Enum.map(@six, &seat/1),
        page: %Document{bookends: ["lantern", "harbour"], full_table: false},
        full_table: false
      )
    end

    defp six_committed(state, bridges \\ @six_bridges) do
      commit_all(state, Enum.zip(@six, bridges))
    end

    test "at a Full table a miss carries N Bridges in roster order" do
      {state, effects} = six_committed(six_full())
      # The Assayer still names a furthest pair; the rule does not use it.
      state = grade(state, effects, 10, ["beacon", "signal"])

      assert Game.view(state, nil).next_bookends == @six_bridges

      state = again(state)
      view = Game.view(state, nil)

      assert view.bookends == @six_bridges
      assert view.attempt.number == 2
      assert Enum.map(view.bookend_chips, & &1.word) == @six_bridges
      assert Enum.map(view.bookend_chips, & &1.seat_id) == Enum.map(@six, &("seat-" <> &1))
    end

    test "Full table off carries the furthest pair, with the roster fallback" do
      {state, effects} = six_committed(six_off())
      state = grade(state, effects, 10, ["beacon", "signal"])

      assert Game.view(state, nil).next_bookends == ["beacon", "signal"]
      assert Game.view(state, nil).next_bookends_chosen? == true
      assert Game.view(again(state), nil).bookends == ["beacon", "signal"]

      {state, _effects} = six_committed(six_off())
      {:ok, state, []} = Game.apply(state, {:verdict_unavailable, %{}})

      assert Game.view(state, nil).next_bookends == ["cairn", "beacon"]
      assert Game.view(state, nil).next_bookends_chosen? == false
    end

    test "join_and names two words with and, and more with commas and a final and" do
      assert Game.join_and(["cairn", "beacon"]) == "cairn and beacon"

      assert Game.join_and(~w(cairn beacon wharf signal torch lamp)) ==
               "cairn, beacon, wharf, signal, torch and lamp"
    end

    test "the next-Bookends projection is any length" do
      {state, effects} = six_committed(six_full())
      state = grade(state, effects, 10)

      assert length(Game.view(state, nil).next_bookends) == 6
    end

    test "an eight-Seat Full table miss carries every Bridge" do
      eight = ~w(Mara Jacob Ada Ida Ola Ora Ivy Ned)
      eight_bookends = ~w(lantern harbour summit ember grove spire ridge hearth)
      eight_bridges = ~w(cairn beacon wharf signal torch lamp stone flare)

      state =
        Game.init(
          seat_limit: 8,
          seats: Enum.map(eight, &seat/1),
          page: %Document{bookends: eight_bookends, full_table: true},
          full_table: true
        )

      {state, effects} = commit_all(state, Enum.zip(eight, eight_bridges))
      state = grade(state, effects, 10, ["beacon", "signal"])

      assert Game.view(state, nil).next_bookends == eight_bridges
      refute Map.has_key?(Game.view(state, nil).reveal, :pairs)

      state = again(state)
      view = Game.view(state, nil)
      assert view.bookends == eight_bridges
      assert Enum.map(view.bookend_chips, & &1.seat_id) == Enum.map(eight, &("seat-" <> &1))
    end

    test "carried Bookends carry their Seat id, and first-Attempt Bookends carry their Give" do
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      {:ok, state, []} =
        Game.apply(
          state,
          {:page_written,
           %{
             bookends: ["cliff", "wax"],
             from: ["Mara", "Jacob"],
             full_table: true
           }}
        )

      first = Game.view(state, nil)
      assert Enum.map(first.bookend_chips, & &1.word) == ["cliff", "wax"]
      assert Enum.map(first.bookend_chips, & &1.give) == ["lighthouse", "candle"]
      assert Enum.all?(first.bookend_chips, &is_nil(&1.mask))

      {state, effects} = commit_all(state, [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      state = grade(state, effects, 10)
      state = again(state)

      carried = Game.view(state, nil)
      assert Enum.map(carried.bookend_chips, & &1.word) == ["cairn", "beacon"]
      assert Enum.map(carried.bookend_chips, & &1.seat_id) == ["seat-Mara", "seat-Jacob"]
      assert Enum.all?(carried.bookend_chips, &is_nil(&1.give))
    end

    test "a carried Bookend shows its Seat's Mask, and a first-Attempt Bookend never does" do
      state = Game.init(seat_limit: 2, seats: [seat("Mara"), seat("Jacob")])

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Mara", give: "lighthouse"}})

      mask_m = %Mask{url: "/media/masks/mask-mara.png", meta: %{}}

      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Mara", mask: mask_m}})

      {:ok, state, _} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-Jacob", give: "candle"}})

      mask_j = %Mask{url: "/media/masks/mask-jacob.png", meta: %{}}

      {:ok, state, []} =
        Game.apply(state, {:mask_landed, %{seat_id: "seat-Jacob", mask: mask_j}})

      {:ok, state, []} =
        Game.apply(
          state,
          {:page_written,
           %{bookends: ["cliff", "wax"], from: ["Mara", "Jacob"], full_table: true}}
        )

      assert Enum.all?(Game.view(state, nil).bookend_chips, &is_nil(&1.mask))

      {state, effects} = commit_all(state, [{"Mara", "cairn"}, {"Jacob", "beacon"}])
      state = grade(state, effects, 10)

      # Still attempt 1 at the reveal: first-Attempt Bookends stay unattributed.
      assert Enum.all?(Game.view(state, nil).bookend_chips, &is_nil(&1.mask))

      state = again(state)
      chips = Game.view(state, nil).bookend_chips

      assert Enum.map(chips, & &1.mask) == [mask_m, mask_j]
    end
  end

  describe "what each viewer may do (#199)" do
    @actions [
      :give,
      :bridge,
      :propose_overrule,
      :vote_overrule,
      :tap_fairness,
      :advance,
      :tap_bookends,
      :next_page
    ]

    @viewers ["seat-Mara", "seat-Jacob", "seat-Ada", "seat-nobody", nil]

    defp give(state, name, give) do
      {:ok, state, _effects} =
        Game.apply(state, {:give_committed, %{seat_id: "seat-" <> name, give: give}})

      state
    end

    # Mara and Jacob play the Page; Ada sits down once it is written, so she
    # watches it from a Seat. Every stop along the way, by name.
    defp page_states do
      empty = Game.init(seat_limit: 6, seats: [seat("Mara")])
      giving = Game.init(seat_limit: 6, seats: [seat("Mara"), seat("Jacob")])
      one_give = give(giving, "Mara", "lighthouse")
      both_gave = give(one_give, "Jacob", "candle")
      {:ok, writing, _} = Game.apply(both_gave, {:start_page, %{seat_id: "seat-Jacob"}})

      {:ok, written, []} =
        Game.apply(writing, {:page_written, %{bookends: ["ocean", "lantern"]}})

      {:ok, bridging, []} = Game.apply(written, {:seat_joined, seat("Ada")})
      {:ok, one_bridge, []} = commit(bridging, "Mara", "coast")
      {:ok, assaying, effects} = commit(one_bridge, "Jacob", "harbour")
      reveal = grade(assaying, effects, 41)

      {:ok, ungraded, _} = Game.apply(assaying, {:verdict_unavailable, %{}})

      {:ok, proposed, []} =
        Game.apply(reveal, {:overrule_proposed, %{seat_id: "seat-Mara", closeness: 60}})

      {:ok, overruled, _} = Game.apply(proposed, {:overrule_agreed, %{seat_id: "seat-Jacob"}})

      {:ok, ungraded_proposed, []} =
        Game.apply(ungraded, {:overrule_proposed, %{seat_id: "seat-Mara", closeness: 60}})

      {:ok, ungraded_overruled, _} =
        Game.apply(ungraded_proposed, {:overrule_agreed, %{seat_id: "seat-Jacob"}})

      second_attempt = again(reveal)
      {closed, _effects} = attempt(second_attempt, [{"Mara", "beam"}, {"Jacob", "beam"}], 95)

      %{
        waiting: empty,
        giving: giving,
        one_give: one_give,
        writing: writing,
        bridging: bridging,
        one_bridge: one_bridge,
        assaying: assaying,
        reveal: reveal,
        ungraded: ungraded,
        proposed: proposed,
        overruled: overruled,
        ungraded_overruled: ungraded_overruled,
        second_attempt: second_attempt,
        closed: closed
      }
    end

    defp may(state, viewer), do: Game.view(state, viewer).may

    defp allowed(state, viewer) do
      may = may(state, viewer)
      for action <- @actions, may[action], do: action
    end

    # A valid event of each action: whatever input it carries is input the Game
    # accepts, so only the viewer's standing can turn it away.
    defp valid_events(:give, seat_id),
      do: [{:give_committed, %{seat_id: seat_id, give: "starlight"}}]

    defp valid_events(:bridge, seat_id),
      do: [{:bridge_committed, %{seat_id: seat_id, bridge: "quill"}}]

    defp valid_events(:propose_overrule, seat_id),
      do: [{:overrule_proposed, %{seat_id: seat_id}}]

    defp valid_events(:vote_overrule, seat_id),
      do: [
        {:overrule_agreed, %{seat_id: seat_id}},
        {:overrule_declined, %{seat_id: seat_id}}
      ]

    defp valid_events(:tap_fairness, seat_id),
      do: [{:fairness_tapped, %{seat_id: seat_id, label: "fair"}}]

    defp valid_events(:advance, seat_id), do: [{:attempt_advanced, %{seat_id: seat_id}}]

    defp valid_events(:tap_bookends, seat_id),
      do: [{:bookends_tapped, %{seat_id: seat_id, label: "great"}}]

    defp valid_events(:next_page, seat_id), do: [{:next_page, %{seat_id: seat_id}}]

    test "a viewer who holds no Seat may do nothing, in any Phase" do
      for {name, state} <- page_states() do
        assert allowed(state, nil) == [], "#{name}: #{inspect(may(state, nil))}"
        assert Map.keys(may(state, nil)) |> Enum.sort() == Enum.sort(@actions)
      end
    end

    test "a seated viewer may do what the Phase is for" do
      states = page_states()

      assert allowed(states.waiting, "seat-Mara") == []
      assert allowed(states.giving, "seat-Mara") == [:give]
      assert allowed(states.one_give, "seat-Mara") == []
      assert allowed(states.one_give, "seat-Jacob") == [:give]
      assert allowed(states.writing, "seat-Mara") == []
      assert allowed(states.bridging, "seat-Mara") == [:bridge]
      assert allowed(states.one_bridge, "seat-Mara") == []
      assert allowed(states.one_bridge, "seat-Jacob") == [:bridge]
      assert allowed(states.assaying, "seat-Mara") == []

      assert allowed(states.reveal, "seat-Mara") ==
               [:propose_overrule, :tap_fairness, :advance]

      assert allowed(states.ungraded, "seat-Mara") == [:propose_overrule, :advance]
      assert allowed(states.proposed, "seat-Mara") == [:vote_overrule, :tap_fairness, :advance]
      assert allowed(states.proposed, "seat-Jacob") == [:vote_overrule, :tap_fairness, :advance]
      assert allowed(states.overruled, "seat-Mara") == [:tap_fairness, :advance]
      assert allowed(states.second_attempt, "seat-Mara") == [:bridge]

      assert allowed(states.closed, "seat-Mara") ==
               [:propose_overrule, :tap_fairness, :tap_bookends, :next_page]
    end

    test "an overrule of an ungraded Attempt can be rated, as the Game accepts the tap" do
      states = page_states()

      assert Game.view(states.ungraded_overruled, nil).phase in [:reveal, :closed]
      assert may(states.ungraded_overruled, "seat-Mara").tap_fairness
    end

    test "a late Seat watches this Page and may only end it" do
      states = page_states()

      for name <- [:bridging, :one_bridge, :assaying, :reveal, :proposed, :second_attempt] do
        assert allowed(Map.fetch!(states, name), "seat-Ada") == [], "#{name}"
      end

      assert allowed(states.closed, "seat-Ada") == [:tap_bookends, :next_page]
    end

    test "every answer in `may` is the answer apply/2 gives a valid event" do
      for {name, state} <- page_states(), viewer <- @viewers, action <- @actions do
        may = may(state, viewer)[action]

        for event <- valid_events(action, viewer) do
          accepted? = match?({:ok, _state, _effects}, Game.apply(state, event))

          assert may == accepted?,
                 "#{name}, #{inspect(viewer)}, #{inspect(event)}: may #{may}, accepted #{accepted?}"
        end
      end
    end

    test "first_revealed? turns on with the Page's first reveal and stays on for the Page" do
      states = page_states()

      for name <- [:waiting, :giving, :one_give, :writing, :bridging, :one_bridge, :assaying],
          viewer <- @viewers do
        refute Game.view(Map.fetch!(states, name), viewer).first_revealed?, "#{name}"
      end

      for name <- [:reveal, :ungraded, :proposed, :overruled, :second_attempt, :closed],
          viewer <- @viewers do
        assert Game.view(Map.fetch!(states, name), viewer).first_revealed?, "#{name}"
      end
    end

    test "the Gives and the Masks go public on first_revealed?" do
      states = page_states()

      for {_name, state} <- states do
        view = Game.view(state, nil)
        assert view.first_revealed? == (view.gives != nil)
      end
    end
  end
end
