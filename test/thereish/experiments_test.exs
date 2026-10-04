defmodule Thereish.ExperimentsTest do
  use Thereish.DataCase, async: false

  import ExUnit.CaptureLog
  import Thereish.EntryFixtures
  import Thereish.ExperimentFixtures
  import Thereish.RoomFixtures

  alias Thereish.Chronicle
  alias Thereish.Chronicle.ExperimentOutcome
  alias Thereish.Experiments
  alias Thereish.Ladder
  alias Thereish.Rooms
  alias Thereish.Rooms.Room

  setup do
    slug = open_room()
    {:ok, mara} = Rooms.join(slug, "Mara", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{room: Repo.get_by!(Room, slug: slug), mara: mara, jacob: jacob}
  end

  # Writes an Entry and records its outcome, as the Room does when a Page closes.
  defp record_outcome(room, attrs) do
    entry = entry(attrs)
    {:ok, page} = Chronicle.write(room.id, entry)
    {:ok, outcome} = Experiments.record_outcome(room.id, page, entry)
    {page, outcome}
  end

  describe "experiment declaration" do
    test "declares author_model experiment" do
      exp = Experiments.definition(:author_model)

      assert exp.id == "author_model"
      assert exp.name =~ "Flash against Astra"
      assert exp.arms == [:flash, :astra]
      assert :meld_rate in exp.declared_outcomes
      assert :attempts_to_meld in exp.declared_outcomes
      assert :bookends_preferences in exp.declared_outcomes
      assert :closing_band in exp.declared_outcomes
    end

    test "keeps bait_against_plain readable" do
      exp = Experiments.definition(:bait_against_plain)

      assert exp.id == "bait_against_plain"
      assert exp.name == "Bait against plain"
      assert exp.arms == [:bait, :plain]
    end
  end

  describe "assigning an arm" do
    test "alternates Flash and Astra across a Room's Pages and records each assignment",
         %{room: room} do
      assert Experiments.default_arm() == :flash

      assert Experiments.assign(room.id) == :flash
      assert Experiments.assign(room.id) == :astra
      assert Experiments.assign(room.id) == :flash

      assignments = Experiments.assignments(room.id, "author_model")
      assert Enum.map(assignments, & &1.arm) == ["flash", "astra", "flash"]
      assert Enum.all?(assignments, &(&1.page_id == nil))
    end

    test "alternates from the Room's own past arms, not another Room's", %{room: room} do
      other = Repo.get_by!(Room, slug: open_room())
      insert_assignment(other.id, arm: "flash")

      assert Experiments.assign(room.id) == :flash
    end

    test "logs and falls back to the default arm rather than raising" do
      log =
        capture_log(fn ->
          assert Experiments.assign("no-such-room") == Experiments.default_arm()
        end)

      assert log =~ "no experiment arm could be assigned, so the Page plays under flash"
    end
  end

  describe "recording a Page's outcome" do
    test "stores the arm the Entry was played under", %{room: room} do
      {_page, outcome} = record_outcome(room, arm: :astra)

      assert outcome.arm == "astra"
    end

    test "files flash and astra under the Author-model experiment and any other arm under Bait against plain",
         %{room: room} do
      for {arm, experiment_id} <- [
            flash: "author_model",
            astra: "author_model",
            bait: "bait_against_plain",
            plain: "bait_against_plain"
          ] do
        {_page, outcome} = record_outcome(room, arm: arm)

        assert outcome.experiment_id == experiment_id, "arm #{arm}"
      end
    end

    test "refuses an Entry with no arm rather than recording an empty one", %{room: room} do
      entry = entry(arm: nil)
      {:ok, page} = Chronicle.write(room.id, entry)

      assert_raise FunctionClauseError, fn ->
        Experiments.record_outcome(room.id, page, entry)
      end

      assert Repo.aggregate(ExperimentOutcome, :count) == 0
    end

    test "reads melded, Closeness, closing band, Attempts and closed-because from the Entry",
         %{room: room} do
      {page, outcome} =
        record_outcome(room,
          arm: :flash,
          closed_because: :attempts_spent,
          melded?: false,
          closeness: 55,
          attempts: [
            %{number: 1, melded?: false, closeness: 30},
            %{number: 2, melded?: false, closeness: 45},
            %{number: 3, melded?: false, closeness: 55}
          ]
        )

      assert outcome.melded == false
      assert outcome.closeness == 55
      assert outcome.closing_band == to_string(Ladder.read(55).band)
      assert outcome.attempts_count == 3
      assert outcome.closed_because == "attempts_spent"
      assert outcome.page_id == page.id
      assert outcome.page_identifier == to_string(page.id)
      assert outcome.taps == %{}
      assert [^outcome] = Experiments.outcomes(room.id, "author_model")
    end

    test "links the Page to the oldest unlinked assignment of its experiment", %{room: room} do
      bait = insert_assignment(room.id, experiment_id: "bait_against_plain", arm: "bait")
      oldest = insert_assignment(room.id, arm: "flash")
      newer = insert_assignment(room.id, arm: "astra")

      {page, _outcome} = record_outcome(room, arm: :flash)

      assert Repo.reload!(oldest).page_id == page.id
      assert Repo.reload!(newer).page_id == nil
      assert Repo.reload!(bait).page_id == nil
    end
  end

  describe "a Bookends tap" do
    test "lands on its Page's outcome, one label per Seat, the latest tap winning", ctx do
      outcome = insert_outcome(ctx.room.id, page_identifier: "P001", arm: "flash")

      tap = fn seat, label ->
        Experiments.record_bookends_tap(ctx.room.id, %{
          page_identifier: "P001",
          seat_id: seat.id,
          label: label,
          bookends: ["lantern", "harbour"],
          gives: %{ctx.mara.id => "light", ctx.jacob.id => "water"},
          author_meta: %{"arm" => "flash"},
          arm: "flash"
        })
      end

      assert {:ok, first} = tap.(ctx.mara, "great")
      assert first.label == "great"
      assert first.arm == "flash"

      assert {:ok, _} = tap.(ctx.mara, "fine")
      assert {:ok, _} = tap.(ctx.jacob, "great")

      assert Repo.reload!(outcome).taps == %{
               to_string(ctx.mara.id) => "fine",
               to_string(ctx.jacob.id) => "great"
             }

      assert length(Experiments.bookends_taps(ctx.room.id)) == 3
    end

    test "finds its outcome by the Page's id", ctx do
      {page, outcome} = record_outcome(ctx.room, arm: :astra)

      assert {:ok, _} =
               Experiments.record_bookends_tap(ctx.room.id, %{
                 page_id: page.id,
                 seat_id: ctx.mara.id,
                 label: "flat"
               })

      assert Repo.reload!(outcome).taps == %{to_string(ctx.mara.id) => "flat"}
    end

    test "with no outcome of its own is recorded alone and updates no other Page's outcome",
         ctx do
      earlier = insert_outcome(ctx.room.id, page_identifier: "P001")

      assert {:ok, tap} =
               Experiments.record_bookends_tap(ctx.room.id, %{
                 page_identifier: "P002",
                 seat_id: ctx.mara.id,
                 label: "great"
               })

      assert tap.page_identifier == "P002"
      assert Repo.reload!(earlier).taps == %{}
      assert [_] = Experiments.bookends_taps(ctx.room.id)
    end
  end

  defp unblind_attrs(seat) do
    %{seat_id: seat.id, unblinded_at: DateTime.utc_now(), notes: "Couch night review"}
  end

  describe "progress toward the declared sample" do
    test "counts completed-Page outcomes across both arms, not assignments without outcomes",
         %{room: room} do
      insert_assignment(room.id, page_identifier: "in-play")

      assert Experiments.progress(room.id, "author_model") == %{
               recorded: 0,
               required: 20,
               ready?: false
             }

      insert_outcomes(room.id, "author_model", 10, arm: "flash")
      insert_outcomes(room.id, "author_model", 9, arm: "astra")

      assert Experiments.progress(room.id, "author_model") == %{
               recorded: 19,
               required: 20,
               ready?: false
             }

      insert_outcomes(room.id, "author_model", 1, arm: "astra")

      assert Experiments.progress(room.id, "author_model") == %{
               recorded: 20,
               required: 20,
               ready?: true
             }
    end
  end

  describe "unblinding" do
    test "is refused until the declared sample is recorded, then allowed", ctx do
      refute Experiments.unblinded?(ctx.room.id, "author_model")
      insert_outcomes(ctx.room.id, "author_model", 19)

      assert {:error, :sample_incomplete} =
               Experiments.unblind(ctx.room.id, "author_model", unblind_attrs(ctx.jacob))

      refute Experiments.unblinded?(ctx.room.id, "author_model")
      assert Experiments.unblindings(ctx.room.id) == []

      insert_outcomes(ctx.room.id, "author_model", 1)

      assert {:ok, unblinding} =
               Experiments.unblind(ctx.room.id, "author_model", unblind_attrs(ctx.jacob))

      assert unblinding.experiment_id == "author_model"
      assert unblinding.seat_id == ctx.jacob.id
      assert unblinding.notes == "Couch night review"
      assert Experiments.unblinded?(ctx.room.id, "author_model")
      assert Experiments.unblinded?(ctx.room.id)
      refute Experiments.unblinded?(ctx.room.id, "bait_against_plain")
      assert [%{experiment_id: "author_model"}] = Experiments.unblindings(ctx.room.id)
    end

    test "with no experiment named unblinds the Room's active experiment", ctx do
      insert_outcomes(ctx.room.id, "author_model", 20)
      insert_outcomes(ctx.room.id, "bait_against_plain", 20)

      assert {:ok, unblinding} = Experiments.unblind(ctx.room.id, nil, unblind_attrs(ctx.jacob))
      assert unblinding.experiment_id == "bait_against_plain"
      refute Experiments.unblinded?(ctx.room.id, "author_model")
    end

    test "with no experiment named waits for the active experiment's sample", ctx do
      insert_outcomes(ctx.room.id, "author_model", 20)
      insert_outcomes(ctx.room.id, "bait_against_plain", 3)

      assert {:error, :sample_incomplete} =
               Experiments.unblind(ctx.room.id, nil, unblind_attrs(ctx.jacob))

      assert Experiments.progress(ctx.room.id, nil) == %{recorded: 3, required: 20, ready?: false}
    end

    test "progress and unblinding stay per Room and per experiment", ctx do
      room_b = Repo.get_by!(Room, slug: open_room())

      insert_outcomes(ctx.room.id, "author_model", 20, arm: "flash")
      insert_outcomes(ctx.room.id, "bait_against_plain", 19, arm: "bait")
      insert_outcomes(room_b.id, "author_model", 20, arm: "flash")

      assert Experiments.progress(ctx.room.id, "author_model").ready?
      refute Experiments.progress(ctx.room.id, "bait_against_plain").ready?
      assert Experiments.progress(room_b.id, "author_model").ready?

      assert {:ok, _} = Experiments.unblind(ctx.room.id, "author_model", unblind_attrs(ctx.jacob))

      assert {:error, :sample_incomplete} =
               Experiments.unblind(ctx.room.id, "bait_against_plain", unblind_attrs(ctx.jacob))

      assert Experiments.unblinded?(ctx.room.id, "author_model")
      refute Experiments.unblinded?(ctx.room.id, "bait_against_plain")
      refute Experiments.unblinded?(room_b.id, "author_model")
    end
  end

  describe "the readout" do
    test "summarizes the Author-model arms from their outcomes and Bookends taps", ctx do
      insert_outcome(ctx.room.id, page_identifier: "P001", arm: "flash", closing_band: "meld")

      insert_outcome(ctx.room.id,
        page_identifier: "P002",
        arm: "astra",
        closing_band: "deep_meld"
      )

      for {page_identifier, seat, label} <- [
            {"P001", ctx.mara, "fine"},
            {"P001", ctx.jacob, "great"},
            {"P002", ctx.mara, "great"}
          ] do
        {:ok, _} =
          Experiments.record_bookends_tap(ctx.room.id, %{
            page_identifier: page_identifier,
            seat_id: seat.id,
            label: label
          })
      end

      readout = Experiments.readout(ctx.room.id, "author_model")

      assert readout.experiment.id == "author_model"
      assert readout.flash.pages_count == 1
      assert readout.astra.pages_count == 1
      assert readout.flash.preferences_summary == "1 great, 1 fine, 0 flat"
      assert readout.astra.preferences_summary == "1 great, 0 fine, 0 flat"
      assert readout.astra.closing_bands == %{"deep_meld" => 1}
      assert readout.summary_narrative =~ "Flash"
      assert readout.summary_narrative =~ "Astra"
    end

    test "summarizes Bait against plain from its outcomes and its Pages' fairness taps", ctx do
      entry = entry(arm: :bait)
      {:ok, page} = Chronicle.write(ctx.room.id, entry)

      insert_outcome(ctx.room.id,
        page_id: page.id,
        page_identifier: page.id,
        experiment_id: "bait_against_plain",
        arm: "bait",
        trap_converged: true
      )

      {:ok, _} =
        Chronicle.record_fairness_tap(ctx.room.id, %{
          page_id: page.id,
          seat_id: ctx.mara.id,
          attempt_number: 1,
          bookends: ["lantern", "harbour"],
          bridges: ["cairn", "cairn"],
          label: "too_harsh"
        })

      readout = Experiments.readout(ctx.room.id, "bait_against_plain")

      assert readout.experiment.id == "bait_against_plain"
      assert readout.bait.pages_count == 1
      assert readout.bait.trap_sprung_count == 1
      assert readout.bait.too_harsh_count == 1
      assert readout.plain.pages_count == 0
      assert readout.summary_narrative =~ "Bait-scored"
    end

    test "falls back to Bait against plain when the Author-model experiment has no outcomes",
         %{room: room} do
      insert_outcome(room.id, experiment_id: "bait_against_plain", arm: "plain")

      readout = Experiments.readout(room.id, "author_model")

      assert readout.experiment.id == "bait_against_plain"
      assert readout.plain.pages_count == 1
    end

    test "with no outcomes at all reads as an empty Author-model readout", %{room: room} do
      readout = Experiments.readout(room.id, "author_model")

      assert readout.experiment.id == "author_model"
      assert readout.flash.pages_count == 0
      assert readout.astra.pages_count == 0
    end
  end

  describe "the overview" do
    test "lists nothing before any experiment row is recorded" do
      assert Experiments.overview() == []
    end

    test "gives each Room's experiments with their progress, and a readout only once unblinded",
         ctx do
      room_b = Repo.get_by!(Room, slug: open_room())

      insert_assignment(ctx.room.id, experiment_id: "author_model", arm: "flash")
      insert_assignment(ctx.room.id, experiment_id: "bait_against_plain", arm: "bait")
      insert_assignment(room_b.id, experiment_id: "author_model", arm: "flash")
      insert_outcomes(ctx.room.id, "author_model", 20, arm: "flash")
      insert_outcomes(ctx.room.id, "bait_against_plain", 3)

      {:ok, _} = Experiments.unblind(ctx.room.id, "author_model", unblind_attrs(ctx.jacob))

      overview = Experiments.overview()

      entry = fn room, experiment_id ->
        Enum.find(overview, &(&1.room.id == room.id and &1.experiment.id == experiment_id))
      end

      assert length(overview) == 3

      author = entry.(ctx.room, "author_model")
      assert author.experiment == Experiments.definition("author_model")
      assert author.unblinded?
      assert author.progress == %{recorded: 20, required: 20, ready?: true}
      assert author.readout == Experiments.readout(ctx.room.id, "author_model")

      bait = entry.(ctx.room, "bait_against_plain")
      refute bait.unblinded?
      assert bait.progress == %{recorded: 3, required: 20, ready?: false}
      assert bait.readout == nil

      other_room = entry.(room_b, "author_model")
      refute other_room.unblinded?
      assert other_room.progress.recorded == 0
      assert other_room.readout == nil
    end
  end
end
