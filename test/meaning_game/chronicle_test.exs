defmodule MeaningGame.ChronicleTest do
  @moduledoc """
  What Postgres holds after a Page has been played.

  These run against real Postgres through the Ecto sandbox, and every Page here
  is played through the Room rather than handed to `MeaningGame.Chronicle`
  directly — the thing worth pinning is that playing a Page writes it down, not
  that a function called with the right map inserts rows.
  """
  use MeaningGame.DataCase, async: false

  import MeaningGame.RoomFixtures

  alias MeaningGame.Chronicle
  alias MeaningGame.Rooms
  alias MeaningGame.Rooms.Room
  alias MeaningGame.Steward

  setup do
    slug = open_room()
    {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{slug: slug, melissa: melissa, jacob: jacob}
  end

  defp play(ctx, melissa_bridge, jacob_bridge) do
    :ok = Rooms.commit_bridge(ctx.slug, ctx.melissa.id, melissa_bridge)
    :ok = Rooms.commit_bridge(ctx.slug, ctx.jacob.id, jacob_bridge)

    await_reveal(ctx.slug)
  end

  defp chronicled(slug) do
    Chronicle.pages(Repo.get_by!(Room, slug: slug).id)
  end

  describe "a closed Page" do
    test "is written down with the document it was played from", ctx do
      play(ctx, "cairn", "cairo")

      assert [page] = chronicled(ctx.slug)
      assert page.document["id"] == "hand-written-1"
      assert page.document["bookends"] == ["lantern", "harbour"]
      assert page.document["bait"] == "lighthouse"
      assert page.closed_because == "meld"
      assert page.melded == true
      assert page.closeness == 80
      assert DateTime.compare(page.opened_at, page.closed_at) in [:lt, :eq]
    end

    test "starts its clock when the Room filled, not when the Room opened" do
      slug = open_room()
      {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())

      # However long the second phone takes to type a name, that time is not
      # part of the ten to fifteen minutes a Page is supposed to fit into.
      Process.sleep(5)
      still_waiting = DateTime.utc_now()
      {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

      play(%{slug: slug, melissa: melissa, jacob: jacob}, "cairn", "cairo")

      assert [page] = chronicled(slug)
      assert DateTime.compare(page.opened_at, still_waiting) in [:gt, :eq]
    end

    test "carries every attempt, in the order they were played", ctx do
      attempt_cap(3)

      play(ctx, "cairn", "beacon")
      :ok = Rooms.next_attempt(ctx.slug, ctx.melissa.id)
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
      play(ctx, "cairn", "cairo")

      assert [page] = chronicled(ctx.slug)
      assert [attempt] = page.attempts

      assert Enum.map(attempt.bridges, &{&1.seat_id, &1.bridge}) == [
               {ctx.melissa.id, "cairn"},
               {ctx.jacob.id, "cairo"}
             ]
    end

    test "keeps the grade that was shown, and who gave it", ctx do
      play(ctx, "cairn", "cairo")

      assert [page] = chronicled(ctx.slug)
      assert [attempt] = page.attempts
      assert [verdict] = attempt.verdicts

      assert verdict.seat_ids == [ctx.melissa.id, ctx.jacob.id]
      assert verdict.bridges == ["cairn", "cairo"]
      assert verdict.graded == true
      assert verdict.closeness == 80
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
      assert verdict.forward == 80
      assert verdict.reverse == 80
      assert verdict.reasoning_reverse =~ "cairo"

      # Markdown export and digest retain reasoning even though screens do not
      room = Repo.get_by!(Room, slug: ctx.slug)
      assert Chronicle.to_markdown(room.id) =~ "- Reasoning: #{verdict.reasoning}"
      assert Chronicle.digest(room.id) =~ "Verdict: 80 (meld) — #{verdict.reasoning}"
    end

    test "records a verdict that never came as a verdict that never came", ctx do
      steward(mode: :unavailable)
      attempt_cap(1)

      play(ctx, "cairn", "cairo")

      assert [page] = chronicled(ctx.slug)
      assert page.closeness == nil
      assert page.melded == false
      assert [attempt] = page.attempts
      assert [verdict] = attempt.verdicts
      assert verdict.graded == false
      assert verdict.closeness == nil
      assert verdict.band == nil
      assert verdict.bridges == ["cairn", "cairo"]
      assert verdict.model == nil
    end

    test "at three Seats is still one verdict row, naming all three Bridges" do
      slug = open_room(seat_limit: 3)
      attempt_cap(1)

      seats =
        for {name, bridge} <- [{"Melissa", "cairn"}, {"Jacob", "cairo"}, {"Ada", "beacon"}] do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          {seat, bridge}
        end

      for {seat, bridge} <- seats, do: :ok = Rooms.commit_bridge(slug, seat.id, bridge)
      await_reveal(slug)

      assert [page] = chronicled(slug)
      assert [attempt] = page.attempts
      assert length(attempt.bridges) == 3
      assert [verdict] = attempt.verdicts
      assert length(verdict.seat_ids) == 3
      assert verdict.bridges == ["cairn", "cairo", "beacon"]
      assert length(verdict.furthest) == 2
    end
  end

  describe "the Chronicle" do
    test "holds one row per Page played, oldest first", ctx do
      play(ctx, "cairn", "cairo")
      :ok = Rooms.next_page(ctx.slug, ctx.melissa.id)
      play(ctx, "mirage", "mirages")

      pages = chronicled(ctx.slug)

      assert length(pages) == 2
      assert Enum.map(pages, & &1.document["id"]) == ["hand-written-1", "hand-written-2"]
    end

    test "is empty until a Page has closed", ctx do
      play(ctx, "cairn", "beacon")

      assert chronicled(ctx.slug) == []
    end

    test "holds nothing for a Page the Room crashed in the middle of", ctx do
      play(ctx, "cairn", "beacon")

      pid = GenServer.whereis(MeaningGame.Rooms.Server.via(ctx.slug))
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      assert chronicled(ctx.slug) == []
    end

    test "records an overrule with machine ruling, couple ruling, and proposer", ctx do
      room_id = Repo.get_by!(Room, slug: ctx.slug).id

      overrule_attrs = %{
        attempt_number: 1,
        proposer_seat_id: ctx.melissa.id,
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
      assert overrule.proposer_seat_id == ctx.melissa.id
      assert overrule.machine_closeness == 41
      assert overrule.couple_closeness == 100
      assert overrule.couple_reasoning =~ "Overruled jointly"

      assert [saved] = Chronicle.overrules(room_id)
      assert saved.id == overrule.id
      assert saved.proposer.name == "Melissa"
    end

    test "records a player correction as an append-only event without mutating history", ctx do
      play(ctx, "cairn", "cairo")

      [page] = chronicled(ctx.slug)
      [attempt] = page.attempts
      [_bridge1, bridge2] = attempt.bridges
      assert bridge2.bridge == "cairo"

      correction_attrs = %{
        page_id: page.id,
        seat_id: ctx.jacob.id,
        attempt_number: 1,
        target: "bridge",
        original_value: "cairo",
        corrected_value: "cairn",
        note: "Typo on phone keyboard"
      }

      assert {:ok, correction} = Chronicle.record_correction(page.room_id, correction_attrs)
      assert correction.page_id == page.id
      assert correction.target == "bridge"
      assert correction.original_value == "cairo"
      assert correction.corrected_value == "cairn"
      assert correction.note == "Typo on phone keyboard"

      # History is NOT mutated: the original bridge row remains exactly as it was written
      fresh_page =
        Repo.get!(MeaningGame.Chronicle.Page, page.id) |> Repo.preload(attempts: :bridges)

      [fresh_attempt] = fresh_page.attempts
      fresh_bridge2 = Enum.find(fresh_attempt.bridges, &(&1.id == bridge2.id))
      assert fresh_bridge2.bridge == "cairo"

      # And the correction is queryable
      assert [saved] = Chronicle.corrections(page.room_id)
      assert saved.id == correction.id
      assert saved.seat.name == "Jacob"
    end

    test "computes the book view from the event log in reverse chronological order", ctx do
      # Play first page: melded
      play(ctx, "cairn", "cairo")

      # Play second page: two attempts to close it
      attempt_cap(2)
      :ok = Rooms.next_page(ctx.slug, ctx.melissa.id)
      play(ctx, "mirage", "oasis")
      :ok = Rooms.next_attempt(ctx.slug, ctx.melissa.id)
      play(ctx, "sand", "dune")

      room = Repo.get_by!(Room, slug: ctx.slug)

      # Record an overrule on page 2 attempt 1
      [p1, p2] = chronicled(ctx.slug)
      p2_attempt1 = hd(p2.attempts)

      {:ok, _overrule} =
        Chronicle.record_overrule(room.id, %{
          page_id: p2.id,
          attempt_number: 1,
          proposer_seat_id: ctx.melissa.id,
          bookends: p2_attempt1.bookends,
          bridges: ["mirage", "oasis"],
          machine_closeness: 40,
          machine_reasoning: "Distinct ideas",
          machine_quip: "A mirage in an oasis",
          couple_closeness: 85,
          couple_reasoning: "We both saw water in the desert"
        })

      # Record a correction on page 1
      {:ok, _correction} =
        Chronicle.record_correction(room.id, %{
          page_id: p1.id,
          seat_id: ctx.jacob.id,
          attempt_number: 1,
          target: "bridge",
          original_value: "cairo",
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
      assert Enum.map(first_attempt.bridges, & &1.seat_name) == ["Melissa", "Jacob"]
      assert Enum.map(first_attempt.bridges, & &1.bridge) == ["cairn", "cairn"]
      jacob_bridge = Enum.find(first_attempt.bridges, &(&1.seat_name == "Jacob"))
      assert jacob_bridge.original_bridge == "cairo"
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
      play(ctx, "cairn", "cairo")

      # Page 2 misses attempt 1, melds attempt 2
      attempt_cap(2)
      :ok = Rooms.next_page(ctx.slug, ctx.melissa.id)
      play(ctx, "mirage", "oasis")
      :ok = Rooms.next_attempt(ctx.slug, ctx.melissa.id)
      play(ctx, "sand", "dune")

      room = Repo.get_by!(Room, slug: ctx.slug)
      [p1, p2] = chronicled(ctx.slug)
      p2_attempt1 = hd(p2.attempts)

      # Record an overrule
      {:ok, _overrule} =
        Chronicle.record_overrule(room.id, %{
          page_id: p2.id,
          attempt_number: 1,
          proposer_seat_id: ctx.melissa.id,
          bookends: p2_attempt1.bookends,
          bridges: ["mirage", "oasis"],
          machine_closeness: 40,
          machine_reasoning: "Distinct ideas",
          machine_quip: "A mirage in an oasis",
          couple_closeness: 85,
          couple_reasoning: "We both saw water in the desert"
        })

      # Record a correction
      {:ok, _correction} =
        Chronicle.record_correction(room.id, %{
          page_id: p1.id,
          seat_id: ctx.jacob.id,
          attempt_number: 1,
          target: "bridge",
          original_value: "cairo",
          corrected_value: "cairn",
          note: "Phone autocorrect"
        })

      # Export to Markdown on demand
      markdown = Chronicle.to_markdown(room.id)
      assert is_binary(markdown)

      # Verify it contains all components of the evening
      assert markdown =~ "Page 1: lantern · harbour"
      assert markdown =~ "Melissa: cairn"
      assert markdown =~ "Jacob: cairn"
      assert markdown =~ "Overrule"
      assert markdown =~ "Distinct ideas"
      assert markdown =~ "We both saw water in the desert"
      assert markdown =~ "Corrections"
      assert markdown =~ "corrected bridge from \"cairo\" to \"cairn\""
      assert markdown =~ "Phone autocorrect"

      # Round-trip parse back from Markdown
      assert {:ok, parsed_evening} = Chronicle.from_markdown(markdown)
      assert length(parsed_evening) == 2

      [roundtrip_p1, roundtrip_p2] = parsed_evening
      assert roundtrip_p1.bookends == ["lantern", "harbour"]
      assert roundtrip_p1.melded == true
      [a1] = roundtrip_p1.attempts
      assert a1.bridges == [{"Melissa", "cairn"}, {"Jacob", "cairn"}]
      assert [c1] = a1.corrections
      assert c1.original == "cairo"
      assert c1.corrected == "cairn"
      assert c1.note == "Phone autocorrect"

      assert length(roundtrip_p2.attempts) == 2
      [p2_a1, _p2_a2] = roundtrip_p2.attempts
      assert p2_a1.bridges == [{"Melissa", "mirage"}, {"Jacob", "oasis"}]
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
      play(ctx, "cairn", "cairo")

      digest = Steward.digest(room.id)
      assert is_binary(digest)
      assert digest =~ "Page 1 (lantern · harbour)"
      assert digest =~ "Melded on attempt 1 (closeness: 80, meld)"
      assert digest =~ "Melissa bridged \"cairn\""
      assert digest =~ "Jacob bridged \"cairo\""

      # Also accepts room slug
      assert Steward.digest(ctx.slug) == digest
    end
  end

  describe "fairness taps and calibration export (ticket 11)" do
    test "records a fairness tap row with all expected fields", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      attrs = %{
        seat_id: ctx.melissa.id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairo"],
        grade: 80,
        band: "meld",
        model: "gemini-3.8-flash",
        prompt_version: "v1",
        label: "fair"
      }

      assert {:ok, tap} = Chronicle.record_fairness_tap(room.id, attrs)
      assert tap.room_id == room.id
      assert tap.seat_id == ctx.melissa.id
      assert tap.bookends == ["lantern", "harbour"]
      assert tap.bridges == ["cairn", "cairo"]
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
          seat_id: ctx.melissa.id,
          attempt_number: 1,
          bookends: ["lantern", "harbour"],
          bridges: ["cairn", "cairo"],
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
          bridges: ["cairn", "cairo"],
          grade: 80,
          band: "meld",
          model: "gemini-3.8-flash",
          prompt_version: "v1",
          label: "fair"
        })

      taps = Chronicle.fairness_taps(room.id)
      assert length(taps) == 2
      assert Enum.find(taps, &(&1.seat_id == ctx.melissa.id)).label == "too_kind"
      assert Enum.find(taps, &(&1.seat_id == ctx.jacob.id)).label == "fair"
    end

    test "calibration export includes everything a calibration needs", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      Chronicle.record_fairness_tap(room.id, %{
        seat_id: ctx.melissa.id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairo"],
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
        bridges: ["cairn", "cairo"],
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
      assert entry1.bridges == ["cairn", "cairo"]
      assert entry1.grade == 80
      assert entry1.band == "meld"
      assert entry1.model == "gemini-3.8-flash"
      assert entry1.prompt_version == "v1"
      assert entry1.label in ["too_kind", "fair"]
      assert entry1.seat_name in ["Melissa", "Jacob"]

      # Test JSON export format that calibration runs consume
      json_export = Chronicle.export_calibration(room.id, :json)
      assert is_binary(json_export)
      assert {:ok, parsed_json} = Jason.decode(json_export)
      assert length(parsed_json) == 2
      assert hd(parsed_json)["bookends"] == ["lantern", "harbour"]
      assert hd(parsed_json)["bridges"] == ["cairn", "cairo"]
      assert hd(parsed_json)["grade"] == 80
      assert hd(parsed_json)["model"] == "gemini-3.8-flash"
      assert hd(parsed_json)["prompt_version"] == "v1"
    end

    test "taps appear in the Chronicle alongside the Page they judge", ctx do
      play(ctx, "cairn", "cairo")
      room = Repo.get_by!(Room, slug: ctx.slug)
      [page] = chronicled(ctx.slug)

      Chronicle.record_fairness_tap(room.id, %{
        page_id: page.id,
        seat_id: ctx.melissa.id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairo"],
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
        bridges: ["cairn", "cairo"],
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
      assert {"Melissa", "fair"} in labels
      assert {"Jacob", "too_harsh"} in labels

      # Markdown export includes fairness taps
      markdown = Chronicle.to_markdown(room.id)
      assert markdown =~ "Fairness"
      assert markdown =~ "Melissa: fair"
      assert markdown =~ "Jacob: too harsh"
    end

    test "pages authored from a Give are tagged with it and appear in the Chronicle that way",
         ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)
      give = "the language of Children's Hospital"

      {:ok, page_attrs} =
        MeaningGame.Pages.insert_page(%{
          id: "P-GIVE-01",
          chapter: give,
          give: give,
          theme: give,
          bookends: ["nurse", "clinic"],
          bait: "hospital",
          deep_bridges: ["triage", "pager"],
          likely_bridges: ["hospital", "triage", "pager"],
          why_these: "Hospital language invites obvious bridges.",
          band_scripts: %{
            "miss" => "m",
            "adjacent" => "a",
            "close" => "c",
            "meld" => "meld",
            "deep_meld" => "dm"
          },
          meta: %{model: "fake-author", prompt_version: "v1", attempts: 1, cost_usd: 0.0}
        })

      # Play the page
      now = DateTime.utc_now()

      entry = %{
        page: page_attrs,
        closed_because: :meld,
        melded?: true,
        closeness: 85,
        attempts: [
          %{
            number: 1,
            bookends: ["nurse", "clinic"],
            closeness: 85,
            melded?: true,
            bridges: [
              %{seat_id: ctx.melissa.id, bridge: "hospital"},
              %{seat_id: ctx.jacob.id, bridge: "hospital"}
            ],
            verdicts: [
              %{
                seat_ids: [ctx.melissa.id, ctx.jacob.id],
                bridges: ["hospital", "hospital"],
                graded?: true,
                closeness: 85,
                band: :meld,
                reasoning: "Both named hospital.",
                quip: "Hospital shift.",
                meta: %{model: "fake", prompt_version: "v1", latency_ms: 100, cost_usd: 0.0}
              }
            ]
          }
        ]
      }

      assert {:ok, _page} = Chronicle.write(room.id, entry, now)

      # In book view:
      [view] = Chronicle.book(room.id)
      assert view.give == give
      assert view.bookends == ["nurse", "clinic"]

      # In Markdown rendering:
      markdown = Chronicle.to_markdown(room.id)
      assert markdown =~ "- Give: #{give}"

      # Round-trips in Markdown parsing:
      assert {:ok, [parsed]} = Chronicle.from_markdown(markdown)
      assert parsed.give == give

      # Appears in digest:
      digest = Chronicle.digest(room.id)
      assert digest =~ "[Give: #{give}]"
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
        - Melissa: cairn
        - Jacob: cairn
      - Closeness: 80 / 100 (meld)
      """

      assert {:ok, [page]} = Chronicle.from_markdown(legacy_markdown)
      assert page.bookends == ["lantern", "harbour"]
      assert [attempt] = page.attempts
      assert attempt.bookends == ["lantern", "harbour"]
    end

    test "assignment and outcome are Chronicle events, blinded until unblinded", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      # 1. Assignment event at Page start
      {:ok, assignment} =
        Chronicle.record_experiment_assignment(room.id, %{
          page_identifier: "P001",
          experiment_id: "bait_against_plain",
          arm: "bait",
          chapter: "the harbour",
          assigned_at: DateTime.utc_now()
        })

      assert assignment.arm == "bait"
      assert assignment.chapter == "the harbour"

      # Initially blinded
      refute Chronicle.experiment_unblinded?(room.id, "bait_against_plain")

      # 2. Outcome event at Page close
      {:ok, outcome} =
        Chronicle.record_experiment_outcome(room.id, %{
          page_identifier: "P001",
          experiment_id: "bait_against_plain",
          arm: "bait",
          melded: true,
          closeness: 75,
          attempts_count: 2,
          closed_because: "meld",
          trap_converged: true
        })

      assert outcome.trap_converged == true
      assert outcome.arm == "bait"

      # Verify events appear in query
      assignments = Chronicle.experiment_assignments(room.id)
      assert Enum.any?(assignments, &(&1.page_identifier == "P001" and &1.arm == "bait"))

      assert [recorded_outcome] = Chronicle.experiment_outcomes(room.id)
      assert recorded_outcome.melded == true

      # Qualitative readout works
      readout = Chronicle.experiment_readout(room.id)
      assert readout.bait.pages_count == 1
      assert readout.bait.melded_count == 1
      assert readout.bait.trap_sprung_count == 1
      assert readout.summary_narrative =~ "Bait-scored"

      # 3. Deliberate unblinding
      {:ok, unblinding} =
        Chronicle.record_experiment_unblinding(room.id, %{
          experiment_id: "bait_against_plain",
          seat_id: ctx.jacob.id,
          unblinded_at: DateTime.utc_now(),
          notes: "Couch night review"
        })

      assert unblinding.experiment_id == "bait_against_plain"
      assert Chronicle.experiment_unblinded?(room.id, "bait_against_plain")
    end
  end

  describe "the two words that landed furthest apart" do
    test "are written down beside the Verdict, so the book can say where the next Bookends came from" do
      slug = open_room(seat_limit: 4)
      room = Repo.get_by!(Room, slug: slug)

      seats =
        for name <- ["Melissa", "Jacob", "Ada", "Sam"] do
          {:ok, seat} = Rooms.join(slug, name, device_token())
          seat
        end

      bridges = ["beacon", "cairn", "lamp", "seagull"]

      entry = %{
        page: %{
          id: "hand-written-4",
          chapter: "harbour",
          bookends: ["lantern", "harbour"],
          bait: "lighthouse",
          deep_bridges: ["cairn"],
          likely_bridges: ["lighthouse", "beacon", "cairn"],
          why_these: "A table of four at the shore.",
          band_scripts: MeaningGame.Steward.Fake.default_band_scripts()
        },
        closed_because: :attempts,
        melded?: false,
        closeness: 27,
        attempts: [
          %{
            number: 1,
            bookends: ["lantern", "harbour"],
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
                graded?: true,
                closeness: 27,
                band: :miss,
                reasoning: "Three of you were at the shore and one of you was not.",
                quip: "The seagull is having its own evening.",
                furthest: ["beacon", "seagull"],
                meta: %{model: "fake", prompt_version: "assay-2", latency_ms: 90, cost_usd: 0.0}
              }
            ]
          }
        ]
      }

      assert {:ok, _page} = Chronicle.write(room.id, entry, DateTime.utc_now())

      [view] = Chronicle.book(room.id)
      [attempt] = view.attempts
      [verdict] = attempt.verdicts

      assert verdict.bridges == bridges
      assert length(verdict.seat_ids) == 4
      assert verdict.furthest == ["beacon", "seagull"]
    end

    test "are absent from a Verdict that never arrived, and that is not an error", ctx do
      room = Repo.get_by!(Room, slug: ctx.slug)

      entry = %{
        page: %{
          id: "hand-written-2",
          chapter: "harbour",
          bookends: ["lantern", "harbour"],
          bait: "lighthouse",
          deep_bridges: ["cairn"],
          likely_bridges: ["lighthouse", "beacon", "cairn"],
          why_these: "A couch evening.",
          band_scripts: MeaningGame.Steward.Fake.default_band_scripts()
        },
        closed_because: :attempts,
        melded?: false,
        closeness: nil,
        attempts: [
          %{
            number: 1,
            bookends: ["lantern", "harbour"],
            closeness: nil,
            melded?: false,
            bridges: [
              %{seat_id: ctx.melissa.id, bridge: "beacon"},
              %{seat_id: ctx.jacob.id, bridge: "cairn"}
            ],
            verdicts: [
              %{
                seat_ids: [ctx.melissa.id, ctx.jacob.id],
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
      }

      assert {:ok, _page} = Chronicle.write(room.id, entry, DateTime.utc_now())

      [view] = Chronicle.book(room.id)
      [attempt] = view.attempts
      [verdict] = attempt.verdicts

      assert verdict.furthest == nil
    end
  end

  describe "recent_quips/2" do
    test "returns recent quips from the database in chronological order", ctx do
      play(ctx, "cairn", "cairo")
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
end
