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
    {:ok, melissa} = Rooms.join(slug, "Melissa", device_token())
    {:ok, jacob} = Rooms.join(slug, "Jacob", device_token())

    %{room: Repo.get_by!(Room, slug: slug), melissa: melissa, jacob: jacob}
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
          gives: %{ctx.melissa.id => "light", ctx.jacob.id => "water"},
          author_meta: %{"arm" => "flash"},
          arm: "flash"
        })
      end

      assert {:ok, first} = tap.(ctx.melissa, "great")
      assert first.label == "great"
      assert first.arm == "flash"

      assert {:ok, _} = tap.(ctx.melissa, "fine")
      assert {:ok, _} = tap.(ctx.jacob, "great")

      assert Repo.reload!(outcome).taps == %{
               to_string(ctx.melissa.id) => "fine",
               to_string(ctx.jacob.id) => "great"
             }

      assert length(Experiments.bookends_taps(ctx.room.id)) == 3
    end

    test "finds its outcome by the Page's id", ctx do
      {page, outcome} = record_outcome(ctx.room, arm: :astra)

      assert {:ok, _} =
               Experiments.record_bookends_tap(ctx.room.id, %{
                 page_id: page.id,
                 seat_id: ctx.melissa.id,
                 label: "flat"
               })

      assert Repo.reload!(outcome).taps == %{to_string(ctx.melissa.id) => "flat"}
    end

    test "with no outcome of its own is recorded alone and updates no other Page's outcome",
         ctx do
      earlier = insert_outcome(ctx.room.id, page_identifier: "P001")

      assert {:ok, tap} =
               Experiments.record_bookends_tap(ctx.room.id, %{
                 page_identifier: "P002",
                 seat_id: ctx.melissa.id,
                 label: "great"
               })

      assert tap.page_identifier == "P002"
      assert Repo.reload!(earlier).taps == %{}
      assert [_] = Experiments.bookends_taps(ctx.room.id)
    end
  end

  describe "blinding" do
    test "an experiment stays blinded in a Room until it is unblinded there", ctx do
      refute Experiments.unblinded?(ctx.room.id, "author_model")
      assert Experiments.unblindings(ctx.room.id) == []

      insert_outcomes(ctx.room.id, "author_model", 20)

      {:ok, _} =
        Chronicle.record_experiment_unblinding(ctx.room.id, %{
          experiment_id: "author_model",
          seat_id: ctx.jacob.id,
          unblinded_at: DateTime.utc_now()
        })

      assert Experiments.unblinded?(ctx.room.id, "author_model")
      assert Experiments.unblinded?(ctx.room.id)
      refute Experiments.unblinded?(ctx.room.id, "bait_against_plain")
      assert [%{experiment_id: "author_model"}] = Experiments.unblindings(ctx.room.id)
    end
  end

  describe "qualitative readout and streaks" do
    test "calculates longest and current meld streaks" do
      assert Experiments.calculate_streaks([true, true, false, true, true, true]) == %{
               longest_meld_streak: 3,
               current_meld_streak: 3
             }

      assert Experiments.calculate_streaks([true, true, true, false]) == %{
               longest_meld_streak: 3,
               current_meld_streak: 0
             }

      assert Experiments.calculate_streaks([]) == %{
               longest_meld_streak: 0,
               current_meld_streak: 0
             }
    end

    test "reports streaks and preferences rather than p-values" do
      data = %{
        bait: %{
          pages_count: 5,
          melded_count: 4,
          melded_history: [true, true, false, true, true],
          attempts_to_meld: [1, 2, 2, 3],
          fairness_taps: %{"fair" => 6, "too_kind" => 1, "too_harsh" => 1},
          overrules_count: 0,
          trap_sprung_count: 2,
          deep_convergence_count: 1
        },
        plain: %{
          pages_count: 5,
          melded_count: 3,
          melded_history: [false, true, true, false, true],
          attempts_to_meld: [1, 3, 4],
          fairness_taps: %{"fair" => 3, "too_kind" => 4, "too_harsh" => 1},
          overrules_count: 1,
          trap_sprung_count: 0,
          deep_convergence_count: 0
        }
      }

      readout = Experiments.qualitative_readout(data)

      # Shows streaks and preferences
      assert readout.bait.meld_rate == "4/5 (80%)"
      assert readout.plain.meld_rate == "3/5 (60%)"
      assert readout.bait.longest_meld_streak == 2
      assert readout.bait.current_meld_streak == 2
      assert readout.plain.longest_meld_streak == 2
      assert readout.plain.current_meld_streak == 1
      assert readout.bait.mean_attempts_to_meld == 2.0
      assert readout.bait.fairness_summary =~ "6 fair"
      assert readout.plain.fairness_summary =~ "too kind"
      assert is_binary(readout.summary_narrative)
      assert readout.summary_narrative =~ "best streak: 2"

      # Strictly NO p-values or statistical hypothesis testing
      refute Map.has_key?(readout, :p_value)
      refute Map.has_key?(readout, :t_stat)
      refute Map.has_key?(readout, :chi_squared)
    end

    test "reports streaks and bookends preferences for author_model" do
      data = %{
        flash: %{
          pages_count: 4,
          melded_count: 3,
          melded_history: [true, true, false, true],
          attempts_to_meld: [1, 2, 2],
          bookends_taps: %{"great" => 4, "fine" => 2, "flat" => 0},
          closing_bands: %{"meld" => 3, "close" => 1}
        },
        astra: %{
          pages_count: 4,
          melded_count: 4,
          melded_history: [true, true, true, true],
          attempts_to_meld: [1, 1, 2, 1],
          bookends_taps: %{"great" => 6, "fine" => 1, "flat" => 1},
          closing_bands: %{"meld" => 2, "deep_meld" => 2}
        }
      }

      readout = Experiments.qualitative_readout(data)

      assert readout.experiment.id == "author_model"
      assert readout.flash.meld_rate == "3/4 (75%)"
      assert readout.astra.meld_rate == "4/4 (100%)"
      assert readout.flash.longest_meld_streak == 2
      assert readout.astra.longest_meld_streak == 4
      assert readout.flash.preferences_summary =~ "4 great"
      assert readout.astra.preferences_summary =~ "6 great"
      assert is_binary(readout.summary_narrative)
      assert readout.summary_narrative =~ "Flash"
      assert readout.summary_narrative =~ "Astra"
    end
  end
end
