defmodule Thereish.ChronicleTest do
  @moduledoc """
  What Postgres holds after a Page has been played.

  These run against real Postgres through the Ecto sandbox, and every Page here
  is played through the Room rather than handed to `Thereish.Chronicle`
  directly — the thing worth pinning is that playing a Page writes it down, not
  that a function called with the right map inserts rows.
  """
  use Thereish.DataCase, async: false

  import Thereish.EntryFixtures
  import Thereish.ExperimentFixtures
  import Thereish.RoomFixtures

  alias Thereish.Chronicle
  alias Thereish.Chronicle.Entry
  alias Thereish.Experiments
  alias Thereish.Game
  alias Thereish.Ladder
  alias Thereish.Mask
  alias Thereish.Rooms
  alias Thereish.Rooms.Pacing
  alias Thereish.Rooms.Room
  alias Thereish.Steward

  setup do
    slug = open_room()
    {:ok, mara} = Rooms.join(slug, "Mara", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{slug: slug, mara: mara, jacob: jacob}
  end

  defp play(ctx, mara_bridge, jacob_bridge) do
    if Rooms.snapshot(ctx.slug, nil).phase == :giving do
      :ok = Rooms.give(ctx.slug, ctx.mara.id, "setting one")
      :ok = Rooms.give(ctx.slug, ctx.jacob.id, "setting two")
      await_phase(ctx.slug, :bridging)
    end

    :ok = Rooms.commit_bridge(ctx.slug, ctx.mara.id, mara_bridge)
    :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, jacob_bridge)

    await_reveal(ctx.slug)
  end

  defp chronicled(slug) do
    Chronicle.pages(Repo.get_by!(Room, slug: slug).id)
  end

  defp insert_historical_correction(room_id, attrs) do
    attrs = Map.put(attrs, :room_id, room_id)

    %Thereish.Chronicle.Correction{}
    |> Thereish.Chronicle.Correction.changeset(attrs)
    |> Repo.insert()
  end

  defp unblind_attrs(seat_id) do
    %{
      seat_id: seat_id,
      unblinded_at: DateTime.utc_now(),
      notes: "Couch night review"
    }
  end

  describe "a closed Page" do
    test "is written down with the document it was played from", ctx do
      play(ctx, "cairn", "cairns")

      assert [page] = chronicled(ctx.slug)
      assert page.author_meta["model"] == "fake-author"
      assert page.document["bookends"] == ["lantern", "harbour"]
      assert page.closed_because == "meld"
      assert page.melded == true
      assert page.closeness == 91
      assert DateTime.compare(page.opened_at, page.closed_at) in [:lt, :eq]
    end

    test "starts its clock when the Room filled, not when the Room opened" do
      slug = open_room()
      {:ok, mara} = Rooms.join(slug, "Mara", device_token())

      # However long the second phone takes to type a name, that time is not
      # part of the ten to fifteen minutes a Page is supposed to fit into.
      Process.sleep(5)
      still_waiting = DateTime.utc_now()
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      play(%{slug: slug, mara: mara, jacob: jacob}, "cairn", "cairns")

      assert [page] = chronicled(slug)
      assert DateTime.compare(page.opened_at, still_waiting) in [:gt, :eq]
    end

    test "carries every attempt, in the order they were played", ctx do
      attempt_cap(3)

      play(ctx, "cairn", "beacon")
      :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)
      play(ctx, "wharf", "gantry")
      :ok = Rooms.next_attempt(ctx.slug, ctx.jacob.id)
      play(ctx, "quay", "quiet")

      assert [page] = chronicled(ctx.slug)
      assert page.closed_because == "attempts_spent"
      assert Enum.map(page.attempts, & &1.number) == [1, 2, 3]

      # The carry-forward is legible from the rows alone: each attempt hangs
      # between the two Bridges that missed on the one before it.
      assert Enum.map(page.attempts, & &1.bookends) == [
               ["lantern", "harbour"],
               ["cairn", "beacon"],
               ["wharf", "gantry"]
             ]

      assert Enum.map(page.attempts, & &1.closeness) == [0, 0, 44]
      assert Enum.map(page.attempts, & &1.melded) == [false, false, false]
    end

    test "says what each Seat wrote, against that Seat", ctx do
      play(ctx, "cairn", "cairns")

      assert [page] = chronicled(ctx.slug)
      assert [attempt] = page.attempts

      assert Enum.map(attempt.bridges, &{&1.seat_id, &1.bridge}) == [
               {ctx.mara.id, "cairn"},
               {ctx.jacob.id, "cairns"}
             ]
    end

    test "keeps the grade that was shown, and who gave it", ctx do
      play(ctx, "cairn", "cairns")

      assert [page] = chronicled(ctx.slug)
      assert [attempt] = page.attempts
      assert [verdict] = attempt.verdicts

      assert verdict.seat_ids == [ctx.mara.id, ctx.jacob.id]
      assert verdict.bridges == ["cairn", "cairns"]
      assert verdict.graded == true
      assert verdict.closeness == 91
      assert verdict.band == "meld"
      assert verdict.reasoning =~ "cairn"

      assert verdict.model == "fake"
      assert verdict.prompt_version == "fake-1"
      assert verdict.latency_ms >= 0
      assert Decimal.eq?(verdict.cost_usd, 0)

      # The joke goes in the book too: the Chronicle is a thing they read, not a
      # table of measurements.
      assert verdict.quip =~ "cairn"

      # And both orderings the grade was the mean of, so that a grade they want
      # to argue with can be argued with in detail.
      assert verdict.forward == 91
      assert verdict.reverse == 91
      assert verdict.reasoning_reverse =~ "cairns"

      # Markdown export and digest retain reasoning even though screens do not
      room = Repo.get_by!(Room, slug: ctx.slug)
      assert Chronicle.to_markdown(room.id) =~ "- Reasoning: #{verdict.reasoning}"
      assert Chronicle.digest(room.id) =~ "Verdict: 91 (meld) — #{verdict.reasoning}"
    end

    test "records a verdict that never came as a verdict that never came", ctx do
      steward(mode: :unavailable)
      attempt_cap(1)

      play(ctx, "cairn", "cairns")

      assert [page] = chronicled(ctx.slug)
      assert page.closeness == nil
      assert page.melded == false
      assert [attempt] = page.attempts
      assert [verdict] = attempt.verdicts
      assert verdict.graded == false
      assert verdict.closeness == nil
      assert verdict.band == nil
      assert verdict.bridges == ["cairn", "cairns"]
      assert verdict.model == nil
    end

    test "at three Seats is still one verdict row, naming all three Bridges" do
      slug = open_room(seat_limit: 3)
      attempt_cap(1)

      seats =
        for {name, bridge} <- [{"Mara", "cairn"}, {"Jacob", "cairns"}, {"Ada", "beacon"}] do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          {seat, bridge}
        end

      for {seat, _bridge} <- seats, do: :ok = Rooms.give(slug, seat.id, "setting #{seat.name}")
      await_phase(slug, :bridging)
      for {seat, bridge} <- seats, do: :ok = Rooms.commit_bridge(slug, seat.id, bridge)
      await_reveal(slug)

      assert [page] = chronicled(slug)
      assert [attempt] = page.attempts
      assert length(attempt.bridges) == 3
      assert [verdict] = attempt.verdicts
      assert length(verdict.seat_ids) == 3
      assert verdict.bridges == ["cairn", "cairns", "beacon"]
      assert length(verdict.furthest) == 2
    end
  end

  describe "the Entry the Game hands over" do
    # The contract between the Game and the Chronicle, without a Room between
    # them: what the pure Game describes at the close, stamped by Pacing, is
    # what the book reads back.
    test "is written as played, and the book reads it back", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      mara = ctx.mara.id
      jacob = ctx.jacob.id
      t0 = ~U[2026-10-03 20:00:00.000000Z]
      at = &DateTime.add(t0, &1, :second)

      verdict = fn closeness ->
        {:verdict_received,
         %{
           closeness: closeness,
           reasoning: "because",
           quip: "A quip.",
           furthest: nil,
           meta: %{model: "test", prompt_version: "v1", latency_ms: 12, cost_usd: 0.0001}
         }}
      end

      steps = [
        {{:seat_joined, %{id: jacob, name: "Jacob"}}, 1},
        {{:give_committed, %{seat_id: mara, give: "a harbour at night"}}, 2},
        {{:give_committed, %{seat_id: jacob, give: "a lantern"}}, 3},
        {{:page_written, %{bookends: ["lantern", "harbour"], meta: %{model: "fake-author"}}}, 4},
        {{:bridge_committed, %{seat_id: mara, bridge: "cairn"}}, 5},
        {{:bridge_committed, %{seat_id: jacob, bridge: "beacon"}}, 6},
        {verdict.(10), 9},
        {{:attempt_advanced, %{seat_id: mara}}, 20},
        {{:bridge_committed, %{seat_id: mara, bridge: "stone"}}, 21},
        {{:bridge_committed, %{seat_id: jacob, bridge: "stone"}}, 22},
        {verdict.(Ladder.meld_threshold() + 5), 29}
      ]

      game = Game.init(seat_limit: 2, seats: [%{id: mara, name: "Mara"}])

      pacing =
        Pacing.new(%{
          beat: 2_500,
          hold: 5_000,
          assayer: [slow: 4_000, unavailable: 10_000],
          author: [still_writing: 5_000, deadline: 8_000]
        })

      {pacing, _game, effects} =
        Enum.reduce(steps, {pacing, game, []}, fn {event, s}, {pacing, game, _effects} ->
          {:ok, moved, effects} = Game.apply(game, event)

          {pacing, _pacing_effects} =
            Pacing.moved(pacing, game, moved, %{ms: s * 1_000, at: at.(s)})

          {pacing, moved, effects}
        end)

      assert [%Entry{} = entry] = for({:chronicle, entry} <- effects, do: entry)
      assert {:ok, page} = Chronicle.write(room.id, Pacing.stamp(pacing, entry))

      assert [view] = Chronicle.page_views(room.id)
      assert view.id == page.id
      assert view.bookends == ["lantern", "harbour"]
      assert view.author_meta["model"] == "fake-author"
      assert view.closed_because == "meld"
      assert view.melded == true
      assert view.closeness == Ladder.meld_threshold() + 5
      assert view.opened_at == at.(1)

      assert Enum.map(view.gives, &{&1.seat_id, &1.text}) == [
               {mara, "a harbour at night"},
               {jacob, "a lantern"}
             ]

      assert [first, second] = view.attempts
      assert first.bookends == ["lantern", "harbour"]
      assert first.closeness == 10
      assert first.melded == false

      assert Enum.map(first.bridges, &{&1.seat_id, &1.bridge}) == [
               {mara, "cairn"},
               {jacob, "beacon"}
             ]

      assert second.bookends == ["cairn", "beacon"]
      assert second.melded == true

      assert [written] = second.verdicts
      assert written.seat_ids == [mara, jacob]
      assert written.bridges == ["stone", "stone"]
      assert written.graded == true
      assert written.band == "meld"
      assert written.reasoning == "because"
      assert written.quip == "A quip."
      assert written.model == "test"

      assert [timing] = Chronicle.page_timings(ctx.slug)
      assert timing.revealed_at == at.(29)
      assert timing.kind == :exact
    end
  end

  describe "the Chronicle" do
    test "holds one row per Page played, oldest first", ctx do
      play(ctx, "cairn", "cairns")
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      play(ctx, "mirage", "mirages")

      pages = chronicled(ctx.slug)

      assert [p1, p2] = pages
      assert DateTime.compare(p1.closed_at, p2.closed_at) in [:lt, :eq]
    end

    test "is empty until a Page has closed", ctx do
      play(ctx, "cairn", "beacon")

      assert chronicled(ctx.slug) == []
    end

    test "holds nothing for a Page the Room crashed in the middle of", ctx do
      play(ctx, "cairn", "beacon")

      pid = GenServer.whereis(Thereish.Rooms.Server.via(ctx.slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert chronicled(ctx.slug) == []
    end

    test "records an overrule with machine ruling, couple ruling, and proposer", ctx do
      room_id = Repo.get_by!(Room, slug: ctx.slug).id

      overrule_attrs = %{
        attempt_number: 1,
        proposer_seat_id: ctx.mara.id,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "beacon"],
        machine_closeness: 41,
        machine_reasoning: "Too far apart.",
        machine_quip: "Not quite.",
        couple_closeness: 100,
        couple_reasoning: "Overruled jointly across all Seats. Recorded as precedent."
      }

      assert {:ok, overrule} = Chronicle.record_overrule(room_id, overrule_attrs)
      assert overrule.room_id == room_id
      assert overrule.proposer_seat_id == ctx.mara.id
      assert overrule.machine_closeness == 41
      assert overrule.couple_closeness == 100
      assert overrule.couple_reasoning =~ "Overruled jointly"

      assert [saved] = Chronicle.overrules(room_id)
      assert saved.id == overrule.id
      assert saved.proposer.name == "Mara"
    end

    test "records a player correction as an append-only event without mutating history", ctx do
      play(ctx, "cairn", "cairns")

      [page] = chronicled(ctx.slug)
      [attempt] = page.attempts
      [_bridge1, bridge2] = attempt.bridges
      assert bridge2.bridge == "cairns"

      correction_attrs = %{
        page_id: page.id,
        seat_id: ctx.jacob.id,
        attempt_number: 1,
        target: "bridge",
        original_value: "cairns",
        corrected_value: "cairn",
        note: "Typo on phone keyboard"
      }

      assert {:ok, correction} = insert_historical_correction(page.room_id, correction_attrs)
      assert correction.page_id == page.id
      assert correction.target == "bridge"
      assert correction.original_value == "cairns"
      assert correction.corrected_value == "cairn"
      assert correction.note == "Typo on phone keyboard"

      # History is NOT mutated: the original bridge row remains exactly as it was written
      fresh_page =
        Repo.get!(Thereish.Chronicle.Page, page.id) |> Repo.preload(attempts: :bridges)

      [fresh_attempt] = fresh_page.attempts
      fresh_bridge2 = Enum.find(fresh_attempt.bridges, &(&1.id == bridge2.id))
      assert fresh_bridge2.bridge == "cairns"

      # And the correction is queryable
      assert [saved] = Chronicle.corrections(page.room_id)
      assert saved.id == correction.id
      assert saved.seat.name == "Jacob"
    end

    test "computes the book view from the event log in reverse chronological order", ctx do
      # Play first page: melded
      play(ctx, "cairn", "cairns")

      # Play second page: two attempts to close it
      attempt_cap(2)
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      play(ctx, "mirage", "oasis")
      :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)
      play(ctx, "sand", "dune")

      room = Repo.get_by!(Room, slug: ctx.slug)

      # Record an overrule on page 2 attempt 1
      [p1, p2] = chronicled(ctx.slug)
      p2_attempt1 = hd(p2.attempts)

      {:ok, _overrule} =
        Chronicle.record_overrule(room.id, %{
          page_id: p2.id,
          attempt_number: 1,
          proposer_seat_id: ctx.mara.id,
          bookends: p2_attempt1.bookends,
          bridges: ["mirage", "oasis"],
          machine_closeness: 40,
          machine_reasoning: "Distinct ideas",
          machine_quip: "A mirage in an oasis",
          couple_closeness: 85,
          couple_reasoning: "We both saw water in the desert"
        })

      # Historical correction on page 1 — writes are retired, the row remains readable
      {:ok, _correction} =
        insert_historical_correction(room.id, %{
          page_id: p1.id,
          seat_id: ctx.jacob.id,
          attempt_number: 1,
          target: "bridge",
          original_value: "cairns",
          corrected_value: "cairn",
          note: "Phone autocorrect"
        })

      # Book view is in reverse chronological order (newest page first)
      book_pages = Chronicle.book(room.id)
      assert length(book_pages) == 2

      [latest_page, first_page] = book_pages
      assert latest_page.id != first_page.id

      # First page in history (which is second in reverse order)
      assert first_page.bookends == ["lantern", "harbour"]
      assert first_page.melded == true
      [first_attempt] = first_page.attempts
      assert Enum.map(first_attempt.bridges, & &1.seat_name) == ["Mara", "Jacob"]
      assert Enum.map(first_attempt.bridges, & &1.bridge) == ["cairn", "cairn"]
      jacob_bridge = Enum.find(first_attempt.bridges, &(&1.seat_name == "Jacob"))
      assert jacob_bridge.original_bridge == "cairns"
      assert jacob_bridge.corrected? == true
      assert [c] = first_page.corrections
      assert c.corrected_value == "cairn"
      assert c.author_name == "Jacob"

      # Latest page
      assert latest_page.closed_because in ["meld", "attempts_spent"]
      assert length(latest_page.attempts) == 2
      assert latest_page.overrules != []
    end

    test "Markdown export round-trips a full evening", ctx do
      # Full evening: Page 1 melds on attempt 1
      play(ctx, "cairn", "cairns")

      # Page 2 misses attempt 1, melds attempt 2
      attempt_cap(2)
      :ok = Rooms.next_page(ctx.slug, ctx.mara.id)
      play(ctx, "mirage", "oasis")
      :ok = Rooms.next_attempt(ctx.slug, ctx.mara.id)
      play(ctx, "sand", "dune")

      room = Repo.get_by!(Room, slug: ctx.slug)
      [p1, p2] = chronicled(ctx.slug)
      p2_attempt1 = hd(p2.attempts)

      # Record an overrule
      {:ok, _overrule} =
        Chronicle.record_overrule(room.id, %{
          page_id: p2.id,
          attempt_number: 1,
          proposer_seat_id: ctx.mara.id,
          bookends: p2_attempt1.bookends,
          bridges: ["mirage", "oasis"],
          machine_closeness: 40,
          machine_reasoning: "Distinct ideas",
          machine_quip: "A mirage in an oasis",
          couple_closeness: 85,
          couple_reasoning: "We both saw water in the desert"
        })

      {:ok, _correction} =
        insert_historical_correction(room.id, %{
          page_id: p1.id,
          seat_id: ctx.jacob.id,
          attempt_number: 1,
          target: "bridge",
          original_value: "cairns",
          corrected_value: "cairn",
          note: "Phone autocorrect"
        })

      # Export to Markdown on demand
      markdown = Chronicle.to_markdown(room.id)
      assert is_binary(markdown)

      # Verify it contains all components of the evening
      assert markdown =~ "Page 1: lantern · harbour"
      assert markdown =~ "Mara: cairn"
      assert markdown =~ "Jacob: cairn"
      assert markdown =~ "Overrule"
      assert markdown =~ "Distinct ideas"
      assert markdown =~ "We both saw water in the desert"
      assert markdown =~ "Corrections"
      assert markdown =~ "corrected bridge from \"cairns\" to \"cairn\""
      assert markdown =~ "Phone autocorrect"
      assert markdown =~ "Spend: "
      spend = Chronicle.spend(room.id)
      assert String.ends_with?(String.trim(markdown), Chronicle.spend_line(spend))

      # Round-trip parse back from Markdown
      assert {:ok, parsed_evening} = Chronicle.from_markdown(markdown)
      assert length(parsed_evening) == 2

      [roundtrip_p1, roundtrip_p2] = parsed_evening
      assert roundtrip_p1.bookends == ["lantern", "harbour"]
      assert roundtrip_p1.melded == true
      [a1] = roundtrip_p1.attempts
      assert a1.bridges == [{"Mara", "cairn"}, {"Jacob", "cairn"}]
      assert [c1] = a1.corrections
      assert c1.original == "cairns"
      assert c1.corrected == "cairn"
      assert c1.note == "Phone autocorrect"

      assert length(roundtrip_p2.attempts) == 2
      [p2_a1, _p2_a2] = roundtrip_p2.attempts
      assert p2_a1.bridges == [{"Mara", "mirage"}, {"Jacob", "oasis"}]
      assert p2_a1.overrule != nil
      assert p2_a1.overrule.original == 40
      assert p2_a1.overrule.overruled == 85
      assert p2_a1.overrule.reasoning =~ "water in the desert"
    end

    test "composes a Steward digest for feeding to models later", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      # Empty room returns default starting message
      assert Steward.digest(room.id) == "Nothing yet; this is the first Page."
      assert Chronicle.digest(room.id) == "Nothing yet; this is the first Page."

      # Play a page
      play(ctx, "cairn", "cairns")

      digest = Steward.digest(room.id)
      assert is_binary(digest)
      assert digest =~ "Page 1 (lantern · harbour)"
      assert digest =~ "Melded on attempt 1 (closeness: 91, meld)"
      assert digest =~ "Mara bridged \"cairn\""
      assert digest =~ "Jacob bridged \"cairns\""

      # Also accepts room slug
      assert Steward.digest(ctx.slug) == digest
    end
  end

  describe "fairness taps and calibration export (ticket 11)" do
    test "records a fairness tap row with all expected fields", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      attrs = %{
        seat_id: ctx.mara.id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairns"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "fair"
      }

      assert {:ok, tap} = Chronicle.record_fairness_tap(room.id, attrs)
      assert tap.room_id == room.id
      assert tap.seat_id == ctx.mara.id
      assert tap.bookends == ["lantern", "harbour"]
      assert tap.bridges == ["cairn", "cairns"]
      assert tap.grade == 80
      assert tap.closeness == 80
      assert tap.band == "meld"
      assert tap.model == "gemini-3.8-flash"
      assert tap.prompt_version == "v1"
      assert tap.label == "fair"
      assert tap.inserted_at != nil
    end

    test "two seats disagreeing about the same grade both persist", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      {:ok, _t1} =
        Chronicle.record_fairness_tap(room.id, %{
          seat_id: ctx.mara.id,
          attempt_number: 1,
          bookends: ["lantern", "harbour"],
          bridges: ["cairn", "cairns"],
          grade: 80,
          band: "meld",
          model: "gemini-3.8-flash",
          prompt_version: "v1",
          label: "too_kind"
        })

      {:ok, _t2} =
        Chronicle.record_fairness_tap(room.id, %{
          seat_id: ctx.jacob.id,
          attempt_number: 1,
          bookends: ["lantern", "harbour"],
          bridges: ["cairn", "cairns"],
          grade: 80,
          band: "meld",
          model: "gemini-3.8-flash",
          prompt_version: "v1",
          label: "fair"
        })

      taps = Chronicle.fairness_taps(room.id)
      assert length(taps) == 2
      assert Enum.find(taps, &(&1.seat_id == ctx.mara.id)).label == "too_kind"
      assert Enum.find(taps, &(&1.seat_id == ctx.jacob.id)).label == "fair"
    end

    test "calibration export includes everything a calibration needs", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      Chronicle.record_fairness_tap(room.id, %{
        seat_id: ctx.mara.id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairns"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "too_kind"
      })

      Chronicle.record_fairness_tap(room.id, %{
        seat_id: ctx.jacob.id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairns"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "fair"
      })

      # Test structured dataset
      dataset = Chronicle.calibration_dataset(room.id)
      assert length(dataset) == 2
      [entry1, _entry2] = dataset

      assert entry1.bookends == ["lantern", "harbour"]
      assert entry1.bridges == ["cairn", "cairns"]
      assert entry1.grade == 80
      assert entry1.band == "meld"
      assert entry1.model == "gemini-3.8-flash"
      assert entry1.prompt_version == "v1"
      assert entry1.label in ["too_kind", "fair"]
      assert entry1.seat_name in ["Mara", "Jacob"]

      # Test JSON export format that calibration runs consume
      json_export = Chronicle.export_calibration(room.id, :json)
      assert is_binary(json_export)
      assert {:ok, parsed_json} = Jason.decode(json_export)
      assert length(parsed_json) == 2
      assert hd(parsed_json)["bookends"] == ["lantern", "harbour"]
      assert hd(parsed_json)["bridges"] == ["cairn", "cairns"]
      assert hd(parsed_json)["grade"] == 80
      assert hd(parsed_json)["model"] == "gemini-3.8-flash"
      assert hd(parsed_json)["prompt_version"] == "v1"
    end

    test "taps appear in the Chronicle alongside the Page they judge", ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = chronicled(ctx.slug)

      Chronicle.record_fairness_tap(room.id, %{
        page_id: page.id,
        seat_id: ctx.mara.id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairns"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "fair"
      })

      Chronicle.record_fairness_tap(room.id, %{
        page_id: page.id,
        seat_id: ctx.jacob.id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairns"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "too_harsh"
      })

      # Book view includes fairness taps on the attempt
      [page_view] = Chronicle.book(room.id)
      [attempt_view] = page_view.attempts
      assert length(attempt_view.fairness_taps) == 2
      labels = Enum.map(attempt_view.fairness_taps, &{&1.seat_name, &1.label})
      assert {"Mara", "fair"} in labels
      assert {"Jacob", "too_harsh"} in labels

      # Markdown export includes fairness taps
      markdown = Chronicle.to_markdown(room.id)
      assert markdown =~ "Fairness"
      assert markdown =~ "Mara: fair"
      assert markdown =~ "Jacob: too harsh"
    end

    test "pages authored from Gives are tagged with them and appear in the Chronicle that way",
         ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      give1 = "the language of Children's Hospital"
      give2 = "cyberpunk nightclub"

      entry =
        entry(
          page: %{bookends: ["nurse", "clinic"]},
          gives: [
            %{seat_id: ctx.mara.id, text: give1},
            %{seat_id: ctx.jacob.id, text: give2}
          ],
          author_meta: %{
            model: "gemini-3.8-flash",
            arm: :flash,
            prompt_version: "author-3",
            cost_usd: 0.0001,
            latency_ms: 150,
            why: "Medical care stands far from late night revelry."
          },
          closeness: 85,
          attempts: [
            %{
              bookends: ["nurse", "clinic"],
              closeness: 85,
              bridges: [
                %{seat_id: ctx.mara.id, bridge: "hospital"},
                %{seat_id: ctx.jacob.id, bridge: "hospital"}
              ],
              verdicts: [
                %{
                  seat_ids: [ctx.mara.id, ctx.jacob.id],
                  bridges: ["hospital", "hospital"],
                  closeness: 85,
                  reasoning: "Both named hospital.",
                  quip: "Hospital shift."
                }
              ]
            }
          ]
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      # In book view:
      [view] = Chronicle.book(room.id)
      assert length(view.gives) == 2
      assert view.bookends == ["nurse", "clinic"]
      assert view.author_meta["model"] == "gemini-3.8-flash"

      # In Markdown rendering:
      markdown = Chronicle.to_markdown(room.id)
      assert markdown =~ "- Give (Mara): #{give1}"
      assert markdown =~ "- Give (Jacob): #{give2}"
      assert markdown =~ "Bookends: nurse · clinic"

      # Round-trips in Markdown parsing:
      assert {:ok, [parsed]} = Chronicle.from_markdown(markdown)
      assert length(parsed.gives) == 2

      # Appears in digest:
      digest = Chronicle.digest(room.id)
      assert digest =~ "[Give (Mara): #{give1}, Give (Jacob): #{give2}]"
    end

    test "from_markdown accepts legacy '- Anchors:' lines for backwards compatibility" do
      legacy_markdown = """
      # The Chronicle

      ## Room: test-room

      ### Page 1: lantern · harbour
      - Outcome: Melded (meld)
      - Closeness: 80 / 100

      #### Attempt 1
      - Anchors: lantern · harbour
      - Bridges:
        - Mara: cairn
        - Jacob: cairn
      - Closeness: 80 / 100 (meld)
      """

      assert {:ok, [page]} = Chronicle.from_markdown(legacy_markdown)
      assert page.bookends == ["lantern", "harbour"]
      assert [attempt] = page.attempts
      assert attempt.bookends == ["lantern", "harbour"]
    end

    test "to_markdown writes Track: line when page has track path and title, and omits it otherwise",
         ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      now = DateTime.utc_now()

      # Page 1: Has a track with path and title
      entry1 =
        entry(
          music_meta: %{
            provider: "mureka",
            path: "/media/tracks/harbour-lights.mp3",
            title: "Harbour Lights"
          },
          opened_at: now
        )

      assert {:ok, _p1} = Chronicle.write(room.id, entry1)

      # Page 2: Has failed score (music_meta has failure, no path)
      entry2 =
        entry(
          page: %{bookends: ["desert", "oasis"]},
          music_meta: %{provider: "mureka", failure: :timed_out, cost_usd: 0.0},
          attempts: [%{bookends: ["desert", "oasis"]}],
          opened_at: DateTime.add(now, 60, :second)
        )

      assert {:ok, _p2} = Chronicle.write(room.id, entry2)

      # Page 3: Music off (music_meta is nil)
      entry3 =
        entry(
          page: %{bookends: ["mountain", "valley"]},
          music_meta: nil,
          attempts: [%{bookends: ["mountain", "valley"]}],
          opened_at: DateTime.add(now, 120, :second)
        )

      assert {:ok, _p3} = Chronicle.write(room.id, entry3)

      markdown = Chronicle.to_markdown(room.id)

      # Page 1 has Track: Harbour Lights
      assert markdown =~ "Page 1: lantern · harbour"
      assert markdown =~ "- Track: Harbour Lights"

      # Page 2 and Page 3 have no Track lines
      assert markdown =~ "Page 2: desert · oasis"
      assert markdown =~ "Page 3: mountain · valley"

      # Exactly one Track: line in the entire document
      matches = Regex.scan(~r/(?:^|\n)-? ?Track:\s*(.*)/, markdown)
      assert length(matches) == 1
      assert hd(matches) |> List.last() |> String.trim() == "Harbour Lights"

      # Round-trip parsing from Markdown
      assert {:ok, [parsed_p1, parsed_p2, parsed_p3]} = Chronicle.from_markdown(markdown)
      assert parsed_p1.track == "Harbour Lights"
      assert parsed_p2.track == nil
      assert parsed_p3.track == nil
    end

    test "from_markdown parses Track: line and legacy exports without Track: still parse" do
      markdown_with_track = """
      # The Chronicle

      ## Room: test-room

      ### Page 1: lantern · harbour
      - Outcome: Melded (meld)
      - Closeness: 80 / 100
      - Track: Midnight Beacon

      #### Attempt 1
      - Bookends: lantern · harbour
      - Bridges:
        - Mara: cairn
        - Jacob: cairn
      - Closeness: 80 / 100 (meld)
      """

      assert {:ok, [page]} = Chronicle.from_markdown(markdown_with_track)
      assert page.track == "Midnight Beacon"

      # Legacy markdown without Track: line still parses cleanly
      legacy_markdown = """
      # The Chronicle

      ## Room: test-room

      ### Page 1: lantern · harbour
      - Outcome: Melded (meld)
      - Closeness: 80 / 100

      #### Attempt 1
      - Bookends: lantern · harbour
      - Bridges:
        - Mara: cairn
        - Jacob: cairn
      - Closeness: 80 / 100 (meld)
      """

      assert {:ok, [legacy_page]} = Chronicle.from_markdown(legacy_markdown)
      assert legacy_page.track == nil
    end
  end

  describe "an experiment's arm in the Chronicle" do
    test "unblinding one experiment does not reveal another experiment's arm in the export",
         ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      now = DateTime.utc_now()

      {:ok, author_page} =
        Chronicle.write(
          room.id,
          entry(
            page: %{
              id: "author-page",
              chapter: "harbour",
              bookends: ["lantern", "harbour"],
              why_these: "A couch night."
            },
            opened_at: now
          )
        )

      {:ok, bait_page} =
        Chronicle.write(
          room.id,
          entry(
            page: %{
              id: "bait-page",
              chapter: "harbour",
              bookends: ["lantern", "harbour"],
              why_these: "A couch night."
            },
            opened_at: DateTime.add(now, 60, :second)
          )
        )

      insert_assignment(room.id, %{
        page_id: author_page.id,
        page_identifier: "author-page",
        experiment_id: "author_model",
        arm: "flash",
        chapter: "harbour",
        assigned_at: now
      })

      insert_outcome(room.id, %{
        page_id: author_page.id,
        page_identifier: "author-page",
        experiment_id: "author_model",
        arm: "flash",
        melded: true,
        closeness: 80,
        attempts_count: 1,
        closed_because: "meld"
      })

      insert_assignment(room.id, %{
        page_id: bait_page.id,
        page_identifier: "bait-page",
        experiment_id: "bait_against_plain",
        arm: "bait",
        chapter: "harbour",
        assigned_at: now
      })

      insert_outcome(room.id, %{
        page_id: bait_page.id,
        page_identifier: "bait-page",
        experiment_id: "bait_against_plain",
        arm: "bait",
        melded: true,
        closeness: 80,
        attempts_count: 1,
        closed_because: "meld"
      })

      insert_outcomes(room.id, "author_model", 19)

      assert {:ok, _} =
               Experiments.unblind(room.id, "author_model", unblind_attrs(ctx.jacob.id))

      views = Chronicle.page_views(room.id)
      author_view = Enum.find(views, &(&1.id == author_page.id))
      bait_view = Enum.find(views, &(&1.id == bait_page.id))

      assert author_view.experiment_unblinded
      assert author_view.arm == "flash"
      refute bait_view.experiment_unblinded
      assert bait_view.arm == nil

      markdown = Chronicle.to_markdown(room.id)
      assert markdown =~ "- Experiment: Author model: Flash against Astra\n- Arm: flash"
      assert markdown =~ "- Experiment: Blinded (bait_against_plain)"
      refute markdown =~ "- Arm: bait"

      assert {:ok, parsed} = Chronicle.from_markdown(markdown)

      assert Enum.map(parsed, &{&1.experiment, &1.arm}) == [
               {"Author model: Flash against Astra", "flash"},
               {"Blinded (bait_against_plain)", nil}
             ]
    end
  end

  describe "the two words that landed furthest apart" do
    test "are written down beside the Verdict, so the book can say where the next Bookends came from" do
      slug = open_room(seat_limit: 4)
      room = Repo.get_by!(Room, slug: slug)

      seats =
        for name <- ["Mara", "Jacob", "Ada", "Sam"] do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          seat
        end

      bridges = ["beacon", "cairn", "lamp", "seagull"]

      entry =
        entry(
          page: %{
            id: "hand-written-4",
            chapter: "harbour",
            bookends: ["lantern", "harbour"],
            why_these: "A table of four at the shore."
          },
          closed_because: :attempts_spent,
          melded?: false,
          closeness: 27,
          attempts: [
            %{
              closeness: 27,
              melded?: false,
              bridges:
                Enum.zip_with(seats, bridges, fn seat, bridge ->
                  %{seat_id: seat.id, bridge: bridge}
                end),
              verdicts: [
                %{
                  seat_ids: Enum.map(seats, & &1.id),
                  bridges: bridges,
                  closeness: 27,
                  band: :miss,
                  reasoning: "Three of you were at the shore and one of you was not.",
                  quip: "The seagull is having its own evening.",
                  furthest: ["beacon", "seagull"]
                }
              ]
            }
          ]
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      [view] = Chronicle.book(room.id)
      [attempt] = view.attempts
      [verdict] = attempt.verdicts

      assert verdict.bridges == bridges
      assert length(verdict.seat_ids) == 4
      assert verdict.furthest == ["beacon", "seagull"]

      # Pages from before the rule still render: no Full table field, Carried is the furthest pair.
      assert view.full_table == nil
      assert attempt.carried == ["beacon", "seagull"]
      markdown = Chronicle.to_markdown(room.id)
      refute markdown =~ "- Rule:"
    end

    test "are absent from a Verdict that never arrived, and that is not an error", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      entry =
        entry(
          page: %{
            id: "hand-written-2",
            chapter: "harbour",
            bookends: ["lantern", "harbour"],
            why_these: "A couch evening."
          },
          closed_because: :attempts_spent,
          melded?: false,
          closeness: nil,
          attempts: [
            %{
              closeness: nil,
              melded?: false,
              bridges: [
                %{seat_id: ctx.mara.id, bridge: "beacon"},
                %{seat_id: ctx.jacob.id, bridge: "cairn"}
              ],
              verdicts: [
                %{
                  seat_ids: [ctx.mara.id, ctx.jacob.id],
                  bridges: ["beacon", "cairn"],
                  graded?: false,
                  closeness: nil,
                  band: nil,
                  reasoning: nil,
                  quip: "No verdict tonight.",
                  meta: %{}
                }
              ]
            }
          ]
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      [view] = Chronicle.book(room.id)
      [attempt] = view.attempts
      [verdict] = attempt.verdicts

      assert verdict.furthest == nil
    end

    test "a four-Seat Page writes four Give rows with their Seats and one Verdict row per Attempt with four Seat ids and the furthest pair" do
      attempt_cap(1)
      code = open_room(seat_limit: 4)
      room = Repo.get_by!(Room, slug: code)

      seats =
        for name <- ["Mara", "Jacob", "Ada", "Sam"] do
          {:ok, seat} = Rooms.join(code, name, device_token())
          seat
        end

      [mara, jacob, ada, sam] = seats

      assert Rooms.snapshot(code, nil).phase == :giving
      :ok = Rooms.give(code, mara.id, "setting one")
      :ok = Rooms.give(code, jacob.id, "setting two")
      :ok = Rooms.give(code, ada.id, "setting three")
      :ok = Rooms.give(code, sam.id, "setting four")

      await_phase(code, :bridging)

      :ok = Rooms.commit_bridge(code, mara.id, "beacon")
      :ok = Rooms.commit_bridge(code, jacob.id, "cairn")
      :ok = Rooms.commit_bridge(code, ada.id, "lamp")
      :ok = Rooms.commit_bridge(code, sam.id, "seagull")

      await_phase(code, :closed)

      # 4 Give rows written with their Seats
      [page] = Chronicle.pages(room.id)

      give_rows =
        Repo.all(
          from(g in Thereish.Chronicle.Give,
            where: g.page_id == ^page.id,
            order_by: [asc: g.order]
          )
        )

      assert length(give_rows) == 4
      assert Enum.map(give_rows, & &1.seat_id) == Enum.map(seats, & &1.id)

      assert Enum.map(give_rows, & &1.text) == [
               "setting one",
               "setting two",
               "setting three",
               "setting four"
             ]

      # One Verdict row per Attempt with 4 Seat ids and the furthest pair
      verdict_rows =
        Repo.all(
          from(v in Thereish.Chronicle.Verdict,
            join: a in assoc(v, :attempt),
            where: a.page_id == ^page.id
          )
        )

      assert [verdict] = verdict_rows
      assert length(verdict.seat_ids) == 4
      assert verdict.seat_ids == Enum.map(seats, & &1.id)
      assert is_list(verdict.furthest) and length(verdict.furthest) == 2
      assert Enum.all?(verdict.furthest, &(&1 in ["beacon", "cairn", "lamp", "seagull"]))

      # Book view lists Gives, every Bridge, the one Verdict with reasoning, and the carried words
      [view] = Chronicle.book(room.id)
      assert length(view.gives) == 4
      [attempt] = view.attempts
      assert length(attempt.bridges) == 4
      assert [v] = attempt.verdicts
      assert v.reasoning != nil and v.reasoning != ""
      assert v.furthest == verdict.furthest
      assert attempt.carried == ["beacon", "cairn", "lamp", "seagull"]
      assert view.full_table == true

      assert Enum.map(view.bookend_origins, & &1.give) == [
               "setting one",
               "setting two",
               "setting three",
               "setting four"
             ]

      assert Enum.map(attempt.bookend_chips, & &1.give) == [
               "setting one",
               "setting two",
               "setting three",
               "setting four"
             ]

      # Markdown export renders every Bridge, the one Verdict, and the carried words
      markdown = Chronicle.to_markdown(room.id)
      assert markdown =~ "Mara: beacon"
      assert markdown =~ "Jacob: cairn"
      assert markdown =~ "Ada: lamp"
      assert markdown =~ "Sam: seagull"
      assert markdown =~ "- Reasoning: #{v.reasoning}"
      assert markdown =~ "- Carried: beacon, cairn, lamp and seagull"
      assert markdown =~ "- Rule: Full table"
      assert markdown =~ "from Mara's setting one"

      # Round-trip parsing from Markdown
      assert {:ok, [parsed_page]} = Chronicle.from_markdown(markdown)
      assert length(parsed_page.gives) == 4
      [parsed_attempt] = parsed_page.attempts
      assert length(parsed_attempt.bridges) == 4
      assert parsed_attempt.carried == ["beacon", "cairn", "lamp", "seagull"]
    end

    test "a book that holds two Verdicts on one Attempt, each covering two Seats, still renders" do
      slug = open_room(seat_limit: 4)
      room = Repo.get_by!(Room, slug: slug)

      seats =
        for name <- ["Mara", "Jacob", "Ada", "Sam"] do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          seat
        end

      [mara, jacob, ada, sam] = seats

      entry =
        entry(
          page: %{
            id: "two-verdicts-on-one-attempt",
            chapter: "harbour",
            bookends: ["lantern", "harbour"],
            why_these: "An earlier night graded the table as two pairs."
          },
          closed_because: :attempts_spent,
          melded?: false,
          closeness: 85,
          attempts: [
            %{
              closeness: 85,
              melded?: false,
              bridges: [
                %{seat_id: mara.id, bridge: "beacon"},
                %{seat_id: jacob.id, bridge: "cairn"},
                %{seat_id: ada.id, bridge: "lamp"},
                %{seat_id: sam.id, bridge: "seagull"}
              ],
              verdicts: [
                %{
                  seat_ids: [mara.id, jacob.id],
                  bridges: ["beacon", "cairn"],
                  closeness: 85,
                  band: :almost,
                  reasoning: "Close on the shore.",
                  quip: "A cairn for the beacon.",
                  furthest: ["beacon", "cairn"]
                },
                %{
                  seat_ids: [ada.id, sam.id],
                  bridges: ["lamp", "seagull"],
                  closeness: 27,
                  band: :miss,
                  reasoning: "The seagull is having its own evening.",
                  quip: "One of you brought a bird.",
                  furthest: ["lamp", "seagull"]
                }
              ]
            }
          ]
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      [view] = Chronicle.book(room.id)
      [attempt] = view.attempts
      assert length(attempt.verdicts) == 2
      assert Enum.map(attempt.verdicts, & &1.closeness) == [85, 27]

      assert Enum.map(attempt.verdicts, & &1.bridges) == [
               ["beacon", "cairn"],
               ["lamp", "seagull"]
             ]

      markdown = Chronicle.to_markdown(room.id)
      assert markdown =~ "Mara: beacon"
      assert markdown =~ "Jacob: cairn"
      assert markdown =~ "Ada: lamp"
      assert markdown =~ "Sam: seagull"
      assert markdown =~ "85 / 100"
      assert markdown =~ "27 / 100"
      assert markdown =~ "Close on the shore."
      assert markdown =~ "The seagull is having its own evening."
    end

    test "calibration export carries the Bridge list on every tap for N seats" do
      code = open_room(seat_limit: 4)
      room = Repo.get_by!(Room, slug: code)

      seats =
        for name <- ["Mara", "Jacob", "Ada", "Sam"] do
          {:ok, seat} = Rooms.join(code, name, device_token())
          seat
        end

      bridges = ["beacon", "cairn", "lamp", "seagull"]

      for seat <- seats do
        Chronicle.record_fairness_tap(room.id, %{
          seat_id: seat.id,
          attempt_number: 1,
          bookends: ["lantern", "harbour"],
          bridges: bridges,
          grade: 27,
          band: "miss",
          model: "gemini-3.8-flash",
          prompt_version: "assay-3",
          label: "fair"
        })
      end

      dataset = Chronicle.calibration_dataset(room.id)
      assert length(dataset) == 4

      for entry <- dataset do
        assert entry.bridges == bridges
      end

      json_export = Chronicle.export_calibration(room.id, :json)
      {:ok, parsed_json} = Jason.decode(json_export)
      assert length(parsed_json) == 4

      for entry <- parsed_json do
        assert entry["bridges"] == bridges
      end
    end

    test "calibration export and Attempt rows carry N Bookends without change of shape" do
      code = open_room(seat_limit: 4)
      room = Repo.get_by!(Room, slug: code)

      seats =
        for name <- ["Mara", "Jacob", "Ada", "Sam"] do
          {:ok, seat} = Rooms.join(code, name, device_token())
          seat
        end

      bookends = ["lantern", "harbour", "wharf", "dusk"]
      bridges = ["beacon", "cairn", "lamp", "seagull"]

      entry =
        entry(
          page: %{
            id: "hand-written-n-bookends",
            chapter: "harbour",
            bookends: bookends,
            why_these: "A Full table at the shore."
          },
          closed_because: :attempts_spent,
          melded?: false,
          closeness: 27,
          attempts: [
            %{
              bookends: bookends,
              closeness: 27,
              melded?: false,
              bridges:
                Enum.zip_with(seats, bridges, fn seat, bridge ->
                  %{seat_id: seat.id, bridge: bridge}
                end),
              verdicts: [
                %{
                  seat_ids: Enum.map(seats, & &1.id),
                  bridges: bridges,
                  closeness: 27,
                  band: :miss,
                  reasoning: "Three of you were at the shore and one of you was not.",
                  quip: "The seagull is having its own evening.",
                  furthest: ["beacon", "seagull"]
                }
              ]
            }
          ]
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      [view] = Chronicle.book(room.id)
      [attempt] = view.attempts
      [verdict] = attempt.verdicts

      assert attempt.bookends == bookends
      assert verdict.bridges == bridges
      assert verdict.furthest == ["beacon", "seagull"]
      assert length(verdict.seat_ids) == 4

      for seat <- seats do
        Chronicle.record_fairness_tap(room.id, %{
          seat_id: seat.id,
          attempt_number: 1,
          bookends: bookends,
          bridges: bridges,
          grade: 27,
          band: "miss",
          model: "gemini-3.8-flash",
          prompt_version: "assay-4",
          label: "fair"
        })
      end

      dataset = Chronicle.calibration_dataset(room.id)
      assert length(dataset) == 4

      for tap <- dataset do
        assert tap.bookends == bookends
        assert tap.bridges == bridges
      end

      json_export = Chronicle.export_calibration(room.id, :json)
      {:ok, parsed_json} = Jason.decode(json_export)

      for tap <- parsed_json do
        assert tap["bookends"] == bookends
        assert is_list(tap["bookends"])
        assert length(tap["bookends"]) == 4
      end
    end
  end

  describe "recent_quips/2" do
    test "returns recent quips from the database in chronological order", ctx do
      play(ctx, "cairn", "cairns")
      quips = Chronicle.recent_quips(ctx.slug, 5)

      assert length(quips) == 1
      assert hd(quips) =~ "walk into a bar"
    end

    test "falls back to priv/chronicles/<slug>.md when room is not in DB" do
      quips = Chronicle.recent_quips("DUST", 5)

      assert length(quips) == 5

      assert List.first(quips) ==
               "Both of you served up plate, proving great minds dish out the same thoughts."

      assert List.last(quips) ==
               "One brought the raw ingredient while the other rolled the meat into a tidy meatball."
    end
  end

  describe "spend (ticket 09)" do
    test "spend/1 for a Room with no pages returns zeros", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      spend = Chronicle.spend(room.id)

      assert Decimal.equal?(spend.total_usd, 0)
      assert spend.calls_count == 0
      assert spend.unpriced_count == 0
      assert spend.by_role.author.calls_count == 0
      assert spend.by_role.assayer.calls_count == 0
      assert spend.by_role.scribe.calls_count == 0
      assert spend.by_model == %{}
      assert Chronicle.spend_line(spend) =~ "Spend: $0.0000"
    end

    test "spend/1 computes totals, by role, and by model from fixture rows including unpriced calls",
         ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      entry =
        entry(
          page: %{bookends: ["desert", "oasis"]},
          author_meta: %{
            model: "gemini-3.8-flash",
            cost_usd: 0.0002
          },
          closeness: 90,
          attempts: [
            %{
              bookends: ["desert", "oasis"],
              closeness: 90,
              bridges: [
                %{seat_id: ctx.mara.id, bridge: "water"},
                %{seat_id: ctx.jacob.id, bridge: "water"}
              ],
              verdicts: [
                %{
                  seat_ids: [ctx.mara.id, ctx.jacob.id],
                  bridges: ["water", "water"],
                  closeness: 90,
                  reasoning: "Both said water.",
                  quip: "Water in the sand.",
                  meta: %{
                    model: "gemini-3.8-flash",
                    cost_usd: 0.0015,
                    prompt_version: "assay-3",
                    latency_ms: 120
                  }
                },
                %{
                  seat_ids: [ctx.mara.id, ctx.jacob.id],
                  bridges: ["water", "water"],
                  graded?: false,
                  closeness: nil,
                  band: nil,
                  reasoning: nil,
                  quip: nil,
                  meta: %{
                    model: "gemini-3.8-flash",
                    cost_usd: nil,
                    prompt_version: "assay-3",
                    latency_ms: nil
                  }
                }
              ]
            }
          ]
        )

      assert {:ok, page} = Chronicle.write(room.id, entry)

      # Add a recap for this page
      {:ok, _recap} =
        Chronicle.record_recap(room.id, %{
          page_id: page.id,
          recap: "A trek through dunes to an oasis.",
          callback: nil,
          model: "claude-fable-5-1",
          cost_usd: 0.0025,
          prompt_version: "recap-2",
          latency_ms: 2500,
          attempts: 1
        })

      # Test querying by ID and by slug
      spend = Chronicle.spend(room.id)
      assert spend == Chronicle.spend(ctx.slug)

      assert Decimal.equal?(spend.total_usd, Decimal.new("0.0042"))
      assert spend.calls_count == 4
      assert spend.unpriced_count == 1

      # By role
      assert spend.by_role.author.calls_count == 1
      assert Decimal.equal?(spend.by_role.author.total_usd, Decimal.new("0.0002"))
      assert spend.by_role.author.unpriced_count == 0

      assert spend.by_role.assayer.calls_count == 2
      assert Decimal.equal?(spend.by_role.assayer.total_usd, Decimal.new("0.0015"))
      assert spend.by_role.assayer.unpriced_count == 1

      assert spend.by_role.scribe.calls_count == 1
      assert Decimal.equal?(spend.by_role.scribe.total_usd, Decimal.new("0.0025"))
      assert spend.by_role.scribe.unpriced_count == 0
      assert spend.by_role.scribe.by_model["claude-fable-5-1"].calls_count == 1

      # By model
      assert spend.by_model["gemini-3.8-flash"].calls_count == 3
      assert Decimal.equal?(spend.by_model["gemini-3.8-flash"].total_usd, Decimal.new("0.0017"))
      assert spend.by_model["gemini-3.8-flash"].unpriced_count == 1

      assert spend.by_model["claude-fable-5-1"].calls_count == 1
      assert Decimal.equal?(spend.by_model["claude-fable-5-1"].total_usd, Decimal.new("0.0025"))
      assert spend.by_model["claude-fable-5-1"].unpriced_count == 0

      # Spend line format
      line = Chronicle.spend_line(spend)
      assert line =~ "Spend: $0.0042"
      assert line =~ "4 calls"
      assert line =~ "1 unpriced"
      assert line =~ "Author $0.0002"
      assert line =~ "Assayer $0.0015"
      assert line =~ "Scribe $0.0025"
      assert line =~ "Foley $0.0000"
      assert line =~ "Limner $0.0000"
    end

    test "spend includes Foley from page music_meta", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      entry =
        entry(
          author_meta: %{model: "gemini-3.8-flash", cost_usd: 0.0002},
          music_meta: %{provider: "mureka", model: "mureka-v1", cost_usd: 0.0400}
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      spend = Chronicle.spend(room.id)
      assert spend.by_role.foley.calls_count == 1
      assert Decimal.equal?(spend.by_role.foley.total_usd, Decimal.new("0.0400"))
      assert spend.by_role.foley.by_model["mureka-v1"].calls_count == 1

      line = Chronicle.spend_line(spend)
      assert line =~ "Foley $0.0400"
    end

    test "spend includes Foley from page vamp_meta beside the Track", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      entry =
        entry(
          author_meta: %{model: "gemini-3.8-flash", cost_usd: 0.0002},
          music_meta: %{provider: "mureka", model: "mureka-v1", cost_usd: 0.0400},
          vamp_meta: %{
            path: "/media/vamps/oasis-vamp.mp3",
            provider: "eleven_labs",
            model: "eleven_text_to_sound_v2",
            cost_usd: 0.0120
          }
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      spend = Chronicle.spend(room.id)
      assert spend.by_role.foley.calls_count == 2
      assert Decimal.equal?(spend.by_role.foley.total_usd, Decimal.new("0.0520"))
      assert spend.by_role.foley.by_model["mureka-v1"].calls_count == 1
      assert spend.by_role.foley.by_model["eleven_text_to_sound_v2"].calls_count == 1

      line = Chronicle.spend_line(spend)
      assert line =~ "Foley $0.0520"
    end

    test "spend counts a zero-cost voice failure as a Foley call", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      entry =
        entry(
          author_meta: %{model: "gemini-3.8-flash", cost_usd: 0.0002},
          attempts: [
            %{
              bridges: [
                %{seat_id: ctx.mara.id, bridge: "water"},
                %{seat_id: ctx.jacob.id, bridge: "water"}
              ],
              verdicts: [
                %{
                  seat_ids: [ctx.mara.id, ctx.jacob.id],
                  bridges: ["water", "water"],
                  meta: %{model: "gemini-3.8-flash", cost_usd: 0.0010},
                  voice_meta: %{
                    "provider" => "fake",
                    "voice" => "fake-voice",
                    "cost_usd" => 0.0,
                    "failure" => "voice_unavailable"
                  }
                }
              ]
            }
          ]
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      spend = Chronicle.spend(room.id)
      assert spend.by_role.foley.calls_count == 1
      assert Decimal.equal?(spend.by_role.foley.total_usd, Decimal.new("0.0000"))
      assert spend.by_role.foley.unpriced_count == 0
      assert spend.by_role.foley.by_model["fake-voice"].calls_count == 1

      assert Decimal.equal?(
               spend.by_role.foley.by_model["fake-voice"].total_usd,
               Decimal.new("0.0000")
             )

      line = Chronicle.spend_line(spend)
      assert line =~ "Foley $0.0000"
    end

    test "spend/0 computes all-Rooms answer with per-Room breakdown across multiple rooms", ctx do
      room1 = Repo.get_by!(Room, slug: ctx.slug)

      entry1 =
        entry(
          author_meta: %{model: "gemini-3.8-flash", cost_usd: 0.0002},
          attempts: [
            %{
              bridges: [
                %{seat_id: ctx.mara.id, bridge: "water"},
                %{seat_id: ctx.jacob.id, bridge: "water"}
              ],
              verdicts: [
                %{
                  seat_ids: [ctx.mara.id, ctx.jacob.id],
                  bridges: ["water", "water"],
                  meta: %{model: "gemini-3.8-flash", cost_usd: 0.0010}
                }
              ]
            }
          ]
        )

      assert {:ok, page1} = Chronicle.write(room1.id, entry1)

      {:ok, _recap1} =
        Chronicle.record_recap(room1.id, %{
          page_id: page1.id,
          recap: "A trek through dunes to an oasis.",
          model: "claude-fable-5-1",
          cost_usd: 0.0030
        })

      # Create a second room with an unpriced author call
      slug2 = open_room()
      room2 = Repo.get_by!(Room, slug: slug2)
      {:ok, seat_a} = Rooms.join(slug2, "Alice", device_token())
      {:ok, seat_b} = Rooms.join(slug2, "Bob", device_token())

      entry2 =
        entry(
          author_meta: %{model: "gemini-3.8-flash", cost_usd: nil},
          attempts: [
            %{
              bridges: [
                %{seat_id: seat_a.id, bridge: "sky"},
                %{seat_id: seat_b.id, bridge: "sky"}
              ],
              verdicts: [
                %{
                  seat_ids: [seat_a.id, seat_b.id],
                  bridges: ["sky", "sky"],
                  meta: %{model: "gemini-3.8-flash", cost_usd: 0.0005}
                }
              ]
            }
          ]
        )

      assert {:ok, _page2} = Chronicle.write(room2.id, entry2)

      # Call spend() for all rooms
      all_spend = Chronicle.spend()

      # Total should be room1 (0.0002 + 0.0010 + 0.0030 = 0.0042) + room2 (0.0005) = 0.0047
      assert Decimal.equal?(all_spend.total_usd, Decimal.new("0.0047"))
      assert all_spend.calls_count == 5
      assert all_spend.unpriced_count == 1

      # By role
      assert Decimal.equal?(all_spend.by_role.author.total_usd, Decimal.new("0.0002"))
      assert all_spend.by_role.author.calls_count == 2
      assert all_spend.by_role.author.unpriced_count == 1

      assert Decimal.equal?(all_spend.by_role.assayer.total_usd, Decimal.new("0.0015"))
      assert all_spend.by_role.assayer.calls_count == 2
      assert all_spend.by_role.assayer.unpriced_count == 0

      assert Decimal.equal?(all_spend.by_role.scribe.total_usd, Decimal.new("0.0030"))
      assert all_spend.by_role.scribe.calls_count == 1

      # Per-room breakdown
      assert is_list(all_spend.rooms)
      room1_spend = Enum.find(all_spend.rooms, &(&1.room_id == room1.id))
      room2_spend = Enum.find(all_spend.rooms, &(&1.room_id == room2.id))

      assert room1_spend != nil
      assert Decimal.equal?(room1_spend.total_usd, Decimal.new("0.0042"))
      assert room1_spend.calls_count == 3
      assert room1_spend.unpriced_count == 0

      assert room2_spend != nil
      assert Decimal.equal?(room2_spend.total_usd, Decimal.new("0.0005"))
      assert room2_spend.calls_count == 2
      assert room2_spend.unpriced_count == 1
    end

    test "pages without author_meta do not count as Author calls or unpriced calls", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      # Write a page with no author_meta (e.g. pre-written seed or human page)
      entry = entry(page: %{bookends: ["left", "right"]}, closeness: 85, attempts: [])

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      spend = Chronicle.spend(room.id)
      assert spend.calls_count == 0
      assert spend.unpriced_count == 0
      assert spend.by_role.author.calls_count == 0
      assert spend.by_role.author.unpriced_count == 0
    end
  end

  describe "masks in Chronicle (ticket 16)" do
    test "Chronicle.write persists masks_meta and page_views includes masks and give masks",
         ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      entry =
        entry(
          gives: [
            %{seat_id: ctx.mara.id, text: "cactus"},
            %{seat_id: ctx.jacob.id, text: "dune"}
          ],
          masks: %{
            ctx.mara.id => %Mask{
              url: "/media/masks/mask-mara.png",
              meta: %{model: "imagen-3", cost_usd: 0.04}
            },
            ctx.jacob.id => %Mask{
              url: "/media/masks/mask-jacob.png",
              meta: %{model: "imagen-3", cost_usd: 0.04}
            }
          }
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      [view] = Chronicle.page_views(room.id)
      assert view.masks[ctx.mara.id].url == "/media/masks/mask-mara.png"
      assert view.masks[ctx.mara.id].meta == %{"model" => "imagen-3", "cost_usd" => 0.04}
      refute Map.has_key?(view, :masks_meta)
      assert [give1, give2] = view.gives
      assert give1.mask.url == "/media/masks/mask-mara.png"
      assert give2.mask.url == "/media/masks/mask-jacob.png"
    end

    test "replace_page_masks/2 updates masks_meta on a Page and spend reflects it", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      entry = entry(masks: %{ctx.mara.id => :dot})

      assert {:ok, page} = Chronicle.write(room.id, entry)
      assert Chronicle.spend(room.id).by_role.limner.calls_count == 0

      updated_masks = %{
        ctx.mara.id => %Mask{
          url: "/media/masks/mask-late.png",
          meta: %{model: "imagen-3", cost_usd: 0.0400}
        }
      }

      assert {:ok, updated_page} = Chronicle.replace_page_masks(page.id, updated_masks)

      assert updated_page.masks_meta[ctx.mara.id].url == "/media/masks/mask-late.png"

      spend = Chronicle.spend(room.id)
      assert spend.by_role.limner.calls_count == 1
      assert Decimal.equal?(spend.by_role.limner.total_usd, Decimal.new("0.0400"))
      assert spend.by_role.limner.by_model["imagen-3"].calls_count == 1

      line = Chronicle.spend_line(spend)
      assert line =~ "Limner $0.0400"
    end

    test "Markdown.render includes masks when present", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      entry =
        entry(
          gives: [%{seat_id: ctx.mara.id, text: "cactus"}],
          masks: %{ctx.mara.id => %Mask{url: "/media/masks/mask-mara.png", meta: %{}}}
        )

      assert {:ok, _page} = Chronicle.write(room.id, entry)

      markdown = Thereish.Chronicle.Markdown.render(room.id)
      assert markdown =~ "/media/masks/mask-mara.png"
    end
  end

  describe "historical feedback without rewriting play (ticket 11, #142)" do
    test "an original participant can mark an Attempt they played too harsh", ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = Chronicle.book(room.id)
      [attempt] = page.attempts

      assert {:ok, opinion} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "too_harsh",
                 as: {:participant, ctx.mara.id}
               })

      assert opinion.label == "too_harsh"
      assert opinion.seat_id == ctx.mara.id
      assert opinion.source == "participant"

      [page_view] = Chronicle.book(room.id)
      [attempt_view] = page_view.attempts
      labels = Enum.map(attempt_view.fairness_taps, &{&1.reviewer_name, &1.label, &1.source})
      assert {"Mara", "too_harsh", "participant"} in labels
    end

    test "a Seat that did not play the Attempt cannot submit participant feedback", ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = Chronicle.book(room.id)
      [attempt] = page.attempts

      outsider_slug = open_room()
      {:ok, outsider} = Rooms.join(outsider_slug, "Ada", device_token())

      assert {:error, :not_a_participant} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "fair",
                 as: {:participant, outsider.id}
               })

      assert Chronicle.fairness_taps(room.id) == []
    end

    test "updating an opinion appends history rather than replacing it", ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = Chronicle.book(room.id)
      [attempt] = page.attempts

      assert {:ok, first} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "fair",
                 as: {:participant, ctx.mara.id}
               })

      assert {:ok, second} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "too_kind",
                 as: {:participant, ctx.mara.id}
               })

      taps = Chronicle.fairness_taps(room.id)
      assert Enum.map(taps, & &1.id) == [first.id, second.id]
      assert Enum.map(taps, & &1.label) == ["fair", "too_kind"]

      [page_view] = Chronicle.book(room.id)
      [attempt_view] = page_view.attempts
      assert Enum.map(attempt_view.fairness_taps, & &1.label) == ["fair", "too_kind"]
    end

    test "the authenticated admin's review is attributed separately from participant opinions",
         ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = Chronicle.book(room.id)
      [attempt] = page.attempts
      admin = Thereish.AdminFixtures.identity()

      assert {:ok, _} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "fair",
                 as: {:participant, ctx.mara.id}
               })

      assert {:ok, admin_review} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "too_kind",
                 as: {:admin, admin.id}
               })

      assert admin_review.source == "admin"
      assert admin_review.admin_id == admin.id
      assert admin_review.seat_id == nil

      [page_view] = Chronicle.book(room.id)
      [attempt_view] = page_view.attempts

      by_source =
        Map.new(attempt_view.fairness_taps, &{{&1.source, &1.reviewer_name}, &1.label})

      assert by_source[{"participant", "Mara"}] == "fair"
      assert by_source[{"admin", "Admin"}] == "too_kind"
      assert Enum.find(attempt_view.fairness_taps, &(&1.source == "admin")).seat_name == nil

      calibration = Chronicle.calibration_dataset(room.id)
      assert length(calibration) == 1
      assert hd(calibration).seat_name == "Mara"
      refute Map.has_key?(hd(calibration), :source)
    end

    test "an unrelated visitor cannot submit or replace participant feedback", ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = Chronicle.book(room.id)
      [attempt] = page.attempts

      assert {:ok, original} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "fair",
                 as: {:participant, ctx.mara.id}
               })

      assert {:error, :not_a_participant} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "too_harsh",
                 as: {:participant, Ecto.UUID.generate()}
               })

      assert {:error, :not_a_participant} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "too_harsh",
                 as: :visitor
               })

      assert {:error, :not_admin} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: attempt.number,
                 label: "too_kind",
                 as: {:admin, Ecto.UUID.generate()}
               })

      assert [saved] = Chronicle.fairness_taps(room.id)
      assert saved.id == original.id
      assert saved.label == "fair"
    end

    test "an opinion on an overruled Attempt evaluates the original grade and leaves the record untouched",
         ctx do
      play(ctx, "cairn", "beacon")
      :ok = Rooms.propose_overrule(ctx.slug, ctx.mara.id)
      :ok = Rooms.agree_overrule(ctx.slug, ctx.jacob.id)

      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = Chronicle.pages(room.id)
      [attempt] = page.attempts
      [verdict] = attempt.verdicts
      [overrule] = Chronicle.overrules(room.id)

      assert overrule.machine_closeness == 0
      assert overrule.couple_closeness == 90
      assert verdict.closeness == 90

      precedents_before =
        Steward.Precedent
        |> Repo.all()
        |> Enum.map(&{&1.id, &1.key, &1.closeness, &1.reasoning})

      refute precedents_before == []

      verdict_before = {verdict.id, verdict.closeness, verdict.overruled, verdict.reasoning}
      overrule_before = {overrule.id, overrule.machine_closeness, overrule.couple_closeness}

      assert {:ok, opinion} =
               Chronicle.record_opinion(room.id, %{
                 page_id: page.id,
                 attempt_number: 1,
                 label: "too_harsh",
                 as: {:participant, ctx.mara.id}
               })

      assert opinion.closeness == 0
      assert opinion.grade == 0

      fresh_verdict = Repo.get!(Thereish.Chronicle.Verdict, verdict.id)

      assert {fresh_verdict.id, fresh_verdict.closeness, fresh_verdict.overruled,
              fresh_verdict.reasoning} ==
               verdict_before

      [fresh_overrule] = Chronicle.overrules(room.id)

      assert {fresh_overrule.id, fresh_overrule.machine_closeness,
              fresh_overrule.couple_closeness} ==
               overrule_before

      precedents_after =
        Steward.Precedent
        |> Repo.all()
        |> Enum.map(&{&1.id, &1.key, &1.closeness, &1.reasoning})

      assert precedents_after == precedents_before
    end

    test "correction writes are rejected while historical corrections remain readable", ctx do
      play(ctx, "cairn", "cairns")
      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = Chronicle.pages(room.id)

      assert {:error, :corrections_retired} =
               Chronicle.record_correction(room.id, %{
                 page_id: page.id,
                 seat_id: ctx.jacob.id,
                 attempt_number: 1,
                 target: "bridge",
                 original_value: "cairns",
                 corrected_value: "cairn",
                 note: "Typo on phone keyboard"
               })

      assert Chronicle.corrections(room.id) == []

      {:ok, historical} =
        %Thereish.Chronicle.Correction{}
        |> Thereish.Chronicle.Correction.changeset(%{
          room_id: room.id,
          page_id: page.id,
          seat_id: ctx.jacob.id,
          attempt_number: 1,
          target: "bridge",
          original_value: "cairns",
          corrected_value: "cairn",
          note: "Phone autocorrect"
        })
        |> Repo.insert()

      assert [saved] = Chronicle.corrections(room.id)
      assert saved.id == historical.id

      [book] = Chronicle.book(room.id)
      jacob_bridge = Enum.find(hd(book.attempts).bridges, &(&1.seat_name == "Jacob"))
      assert jacob_bridge.bridge == "cairn"
      assert jacob_bridge.original_bridge == "cairns"
      assert jacob_bridge.corrected? == true
      assert [c] = book.corrections
      assert c.corrected_value == "cairn"
      assert c.author_name == "Jacob"
    end
  end

  describe "vamps in Chronicle (ticket 08, #139)" do
    test "a written Page keeps its Vamp beside its Track, and a Page with none invents no audio",
         ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      now = DateTime.utc_now()

      assert {:ok, with_both} =
               Chronicle.write(
                 room.id,
                 entry(
                   music_meta: %{
                     path: "/media/tracks/harbour-lights.mp3",
                     title: "Harbour Lights"
                   },
                   vamp_meta: %{
                     path: "/media/vamps/harbour-vamp.mp3",
                     duration: 30,
                     format: "mp3",
                     loop: true,
                     provider: "fake"
                   },
                   opened_at: now
                 )
               )

      assert {:ok, without} =
               Chronicle.write(
                 room.id,
                 entry(
                   page: %{bookends: ["desert", "oasis"]},
                   music_meta: nil,
                   vamp_meta: nil,
                   attempts: [%{bookends: ["desert", "oasis"]}],
                   opened_at: DateTime.add(now, 60, :second)
                 )
               )

      views = Chronicle.page_views(room.id)
      both_view = Enum.find(views, &(&1.id == with_both.id))
      without_view = Enum.find(views, &(&1.id == without.id))

      assert vamp = Chronicle.page_vamp(both_view)
      assert vamp.path == "/media/vamps/harbour-vamp.mp3"
      assert vamp.loop == true
      assert vamp.duration == 30

      assert track = Chronicle.page_track(both_view)
      assert track.path == "/media/tracks/harbour-lights.mp3"
      assert track.title == "Harbour Lights"

      assert Chronicle.page_vamp(without_view) == nil
      assert Chronicle.page_track(without_view) == nil
    end

    test "replace_page_vamp attaches a late Vamp to the Page without touching its Track", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      assert {:ok, page} =
               Chronicle.write(
                 room.id,
                 entry(
                   music_meta: %{
                     path: "/media/tracks/harbour-lights.mp3",
                     title: "Harbour Lights"
                   }
                 )
               )

      assert Chronicle.page_vamp(page) == nil

      assert {:ok, updated} =
               Chronicle.replace_page_vamp(page.id, %{
                 path: "/media/vamps/late-harbour.mp3",
                 duration: 30,
                 loop: true
               })

      [view] = Chronicle.page_views(room.id)
      assert view.id == updated.id
      assert Chronicle.page_vamp(view).path == "/media/vamps/late-harbour.mp3"
      assert Chronicle.page_track(view).path == "/media/tracks/harbour-lights.mp3"
      assert Chronicle.page_track(view).title == "Harbour Lights"
    end

    test "to_markdown writes a Vamp line beside Track when the Page has one, and omits it otherwise",
         ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      now = DateTime.utc_now()

      assert {:ok, _} =
               Chronicle.write(
                 room.id,
                 entry(
                   music_meta: %{
                     path: "/media/tracks/harbour-lights.mp3",
                     title: "Harbour Lights"
                   },
                   vamp_meta: %{
                     path: "/media/vamps/harbour-vamp.mp3",
                     loop: true
                   },
                   opened_at: now
                 )
               )

      assert {:ok, _} =
               Chronicle.write(
                 room.id,
                 entry(
                   page: %{bookends: ["desert", "oasis"]},
                   music_meta: %{
                     path: "/media/tracks/oasis.mp3",
                     title: "Oasis"
                   },
                   attempts: [%{bookends: ["desert", "oasis"]}],
                   opened_at: DateTime.add(now, 60, :second)
                 )
               )

      markdown = Chronicle.to_markdown(room.id)

      assert markdown =~ "- Track: Harbour Lights"
      assert markdown =~ "- Vamp: the short piece"
      assert markdown =~ "- Track: Oasis"

      vamp_matches = Regex.scan(~r/(?:^|\n)-? ?Vamp:\s*(.*)/, markdown)
      assert length(vamp_matches) == 1
      assert hd(vamp_matches) |> List.last() |> String.trim() == "the short piece"

      assert {:ok, [parsed_with, parsed_without]} = Chronicle.from_markdown(markdown)
      assert parsed_with.track == "Harbour Lights"
      assert parsed_with.vamp == "the short piece"
      assert parsed_without.track == "Oasis"
      assert parsed_without.vamp == nil
    end
  end
end
