defmodule Thereish.ExperimentsTest do
  use Thereish.DataCase, async: false

  import ExUnit.CaptureLog
  import Thereish.EntryFixtures
  import Thereish.ExperimentFixtures
  import Thereish.RoomFixtures

  alias Thereish.Chronicle
  alias Thereish.Chronicle.Document
  alias Thereish.ExperimentFixtures
  alias Thereish.Experiments
  alias Thereish.Experiments.Assignment
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

  # Writes a closed Page whose document carries its own id, as the Author does.
  defp write_page(room, document_id) do
    {:ok, page} =
      Chronicle.write(
        room.id,
        entry(page: %Document{identifier: document_id, bookends: ["lantern", "harbour"]})
      )

    page
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

    test "declares the channel experiment" do
      exp = Experiments.definition(:channel)

      assert exp.id == "channel"
      assert exp.name =~ "Nudge on against off"
      assert exp.arms == [:nudge_on, :nudge_off]
      assert exp.sample_size == 20

      assert exp.declared_outcomes == [
               :meld_rate,
               :attempts_to_meld,
               :closing_band,
               :bookends_preferences
             ]
    end

    test "refuses an id nothing declares rather than answering with a live Experiment" do
      assert_raise ArgumentError, ~r/no Experiment is declared as "rungs"/, fn ->
        Experiments.definition("rungs")
      end
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
      first = Experiments.assign(room.id)
      second = Experiments.assign(room.id)
      third = Experiments.assign(room.id)

      assert Enum.map([first, second, third], & &1.arm) == [:flash, :astra, :flash]

      assignments = ExperimentFixtures.assignments(room.id, "author_model")
      assert Enum.map(assignments, & &1.arm) == ["flash", "astra", "flash"]
      assert Enum.all?(assignments, &(&1.page_id == nil))
    end

    test "answers an Assignment naming its own row, its Experiment and its Arm", %{room: room} do
      assert %Assignment{id: id, experiment_id: "author_model", arm: :flash} =
               Experiments.assign(room.id)

      assert [%{id: ^id}] = ExperimentFixtures.assignments(room.id, "author_model")
    end

    test "alternates from the Room's own past arms, not another Room's", %{room: room} do
      other = Repo.get_by!(Room, slug: open_room())
      insert_assignment(other.id, arm: "flash")

      assert Experiments.assign(room.id).arm == :flash
    end

    test "alternates the channel arm on its own rows, beside the Author's", %{room: room} do
      pages = for _ <- 1..3, do: Experiments.assign(room.id)

      assert Enum.map(pages, & &1.arm) == [:flash, :astra, :flash]
      assert Enum.map(pages, &Assignment.arm(&1, :channel)) == [:nudge_on, :nudge_off, :nudge_on]

      channel = ExperimentFixtures.assignments(room.id, "channel")
      assert Enum.map(channel, & &1.arm) == ["nudge_on", "nudge_off", "nudge_on"]

      # Both of a Page's rows name the Page the same way, so its Arms read as
      # one Page.
      assert Enum.map(channel, & &1.page_identifier) ==
               Enum.map(
                 ExperimentFixtures.assignments(room.id, "author_model"),
                 & &1.page_identifier
               )
    end

    test "alternates the channel arm from the Room's own channel rows", %{room: room} do
      insert_assignment(room.id, experiment_id: "channel", arm: "nudge_on")

      assert Assignment.arm(Experiments.assign(room.id), :channel) == :nudge_off
    end

    test "a Room with Nudges off skips the channel sample and resumes its alternation", %{
      room: room
    } do
      assert Assignment.arm(Experiments.assign(room.id), :channel) == :nudge_on
      :ok = Rooms.toggle(room.slug, :nudges)

      skipped = Experiments.assign(room.slug)
      assert skipped.arm == :astra
      assert Assignment.arm(skipped, :channel) == nil
      assert [%{arm: "nudge_on"}] = ExperimentFixtures.assignments(room.id, "channel")

      {_page, _outcome} = record_outcome(room, assignment: skipped)
      assert ExperimentFixtures.outcomes(room.id, "channel") == []
      assert Experiments.progress(room.id, "channel").recorded == 0
      assert Experiments.progress(room.id, "author_model").recorded == 1

      :ok = Rooms.toggle(room.slug, :nudges)
      resumed = Experiments.assign(room.id)
      assert resumed.arm == :flash
      assert Assignment.arm(resumed, :channel) == :nudge_off
      assert Assignment.arm(Experiments.assign(room.id), :channel) == :nudge_on
    end

    test "answers no channel arm at all when no row could be written" do
      log =
        capture_log(fn ->
          assert Assignment.arm(Experiments.assign("no-such-room"), :channel) == nil
        end)

      assert log =~ "no experiment arm could be assigned"
    end

    test "logs and falls back to the default arm, with no row, rather than raising" do
      log =
        capture_log(fn ->
          assert Experiments.assign("no-such-room") ==
                   %Assignment{id: nil, experiment_id: "author_model", arm: :flash}
        end)

      assert log =~ "no experiment arm could be assigned, so the Page plays under flash"
    end
  end

  describe "recording a Page's outcome" do
    test "stores the arm of the Entry's Assignment", %{room: room} do
      {_page, outcome} = record_outcome(room, assignment: Experiments.assign(room.id))
      {_page, outcome2} = record_outcome(room, assignment: Experiments.assign(room.id))

      assert {outcome.arm, outcome2.arm} == {"flash", "astra"}
    end

    test "records the Page under every Experiment it played under, linking each row",
         %{room: room} do
      assignment = Experiments.assign(room.id)
      {page, outcome} = record_outcome(room, assignment: assignment)

      assert {outcome.experiment_id, outcome.arm} == {"author_model", "flash"}

      assert [channel] = ExperimentFixtures.outcomes(room.id, "channel")
      assert {channel.arm, channel.page_id} == {"nudge_on", page.id}

      assert Enum.all?(
               ExperimentFixtures.assignments(room.id, "channel"),
               &(&1.page_id == page.id)
             )
    end

    test "files the outcome under the Assignment's own Experiment", %{room: room} do
      assignment = %Assignment{id: nil, experiment_id: "bait_against_plain", arm: :plain}

      {_page, outcome} = record_outcome(room, assignment: assignment)

      assert {outcome.experiment_id, outcome.arm} == {"bait_against_plain", "plain"}
    end

    test "records an Entry with no Assignment under the default, linking no row",
         %{room: room} do
      unlinked = insert_assignment(room.id, arm: "flash")

      {_page, outcome} = record_outcome(room, assignment: nil)

      assert {outcome.experiment_id, outcome.arm} == {"author_model", "flash"}
      assert Repo.reload!(unlinked).page_id == nil
    end

    test "reads melded, Closeness, closing band, Attempts and closed-because from the Entry",
         %{room: room} do
      {page, outcome} =
        record_outcome(room,
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
      assert [^outcome] = ExperimentFixtures.outcomes(room.id, "author_model")
    end

    test "links its Assignment's own row, not an orphan assigned before it", %{room: room} do
      orphan = Experiments.assign(room.id)
      assignment = Experiments.assign(room.id)

      {page, _outcome} = record_outcome(room, assignment: assignment)

      [orphan_row, row] = ExperimentFixtures.assignments(room.id, "author_model")
      assert {orphan_row.id, orphan_row.page_id} == {orphan.id, nil}
      assert {row.id, row.page_id} == {assignment.id, page.id}

      insert_outcomes(room.id, "author_model", 19)
      {:ok, _} = Experiments.unblind(room.id, "author_model", %{unblinded_at: DateTime.utc_now()})

      assert Experiments.page_arm(Experiments.page_arms(room.id), page).arm == "astra"
    end

    test "leaves a row already linked to another Page alone", %{room: room} do
      assignment = Experiments.assign(room.id)
      {first, _outcome} = record_outcome(room, assignment: assignment)
      {_second, _outcome} = record_outcome(room, assignment: assignment)

      assert [%{page_id: page_id}] = ExperimentFixtures.assignments(room.id, "author_model")
      assert page_id == first.id
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

      assert length(ExperimentFixtures.bookends_taps(ctx.room.id)) == 3
    end

    test "is recorded under the Arm of the Assignment it carries", ctx do
      assignment = %Assignment{id: nil, experiment_id: "author_model", arm: :astra}

      assert {:ok, tap} =
               Experiments.record_bookends_tap(ctx.room.id, %{
                 page_identifier: "P001",
                 seat_id: ctx.mara.id,
                 label: "fine",
                 assignment: assignment
               })

      assert tap.arm == "astra"
    end

    test "finds its outcome by the Page's id", ctx do
      {page, outcome} = record_outcome(ctx.room, assignment: Experiments.assign(ctx.room.id))

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
      assert [_] = ExperimentFixtures.bookends_taps(ctx.room.id)
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
      refute ExperimentFixtures.unblinded?(ctx.room.id, "author_model")
      insert_outcomes(ctx.room.id, "author_model", 19)

      assert {:error, :sample_incomplete} =
               Experiments.unblind(ctx.room.id, "author_model", unblind_attrs(ctx.jacob))

      refute ExperimentFixtures.unblinded?(ctx.room.id)

      insert_outcomes(ctx.room.id, "author_model", 1)

      assert {:ok, unblinding} =
               Experiments.unblind(ctx.room.id, "author_model", unblind_attrs(ctx.jacob))

      assert unblinding.experiment_id == "author_model"
      assert unblinding.seat_id == ctx.jacob.id
      assert unblinding.notes == "Couch night review"
      assert ExperimentFixtures.unblinded?(ctx.room.id, "author_model")
      assert ExperimentFixtures.unblinded?(ctx.room.id)
      refute ExperimentFixtures.unblinded?(ctx.room.id, "bait_against_plain")
    end

    test "with no experiment named unblinds the Room's active experiment", ctx do
      insert_outcomes(ctx.room.id, "author_model", 20)
      insert_outcomes(ctx.room.id, "bait_against_plain", 20)

      assert {:ok, unblinding} = Experiments.unblind(ctx.room.id, nil, unblind_attrs(ctx.jacob))
      assert unblinding.experiment_id == "bait_against_plain"
      refute ExperimentFixtures.unblinded?(ctx.room.id, "author_model")
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

      assert ExperimentFixtures.unblinded?(ctx.room.id, "author_model")
      refute ExperimentFixtures.unblinded?(ctx.room.id, "bait_against_plain")
      refute ExperimentFixtures.unblinded?(room_b.id, "author_model")
    end
  end

  describe "a Page's arm" do
    test "is hidden until its experiment is unblinded, then shown with its convergence", ctx do
      page = write_page(ctx.room, "doc-1")

      insert_assignment(ctx.room.id,
        page_id: page.id,
        experiment_id: "bait_against_plain",
        arm: "plain"
      )

      insert_outcome(ctx.room.id,
        page_id: page.id,
        experiment_id: "bait_against_plain",
        arm: "plain",
        trap_converged: true,
        deep_converged: false
      )

      assert Experiments.page_arm(Experiments.page_arms(ctx.room.id), page) == %{
               experiment_id: "bait_against_plain",
               experiment_unblinded: false,
               arm: nil,
               trap_converged: nil,
               deep_converged: nil
             }

      insert_outcomes(ctx.room.id, "bait_against_plain", 19)
      {:ok, _} = Experiments.unblind(ctx.room.id, "bait_against_plain", unblind_attrs(ctx.jacob))

      assert Experiments.page_arm(Experiments.page_arms(ctx.room.id), page) == %{
               experiment_id: "bait_against_plain",
               experiment_unblinded: true,
               arm: "plain",
               trap_converged: true,
               deep_converged: false
             }
    end

    test "is matched by the Page's own identifier when its rows name no Page id", ctx do
      page = write_page(ctx.room, "doc-2")
      insert_assignment(ctx.room.id, page_identifier: "doc-2", arm: "astra")
      insert_outcomes(ctx.room.id, "author_model", 20)
      {:ok, _} = Experiments.unblind(ctx.room.id, "author_model", unblind_attrs(ctx.jacob))

      assert %{experiment_id: "author_model", experiment_unblinded: true, arm: "astra"} =
               Experiments.page_arm(Experiments.page_arms(ctx.room.id), page)
    end

    test "takes the arm of an outcome when the Page has no assignment", ctx do
      page = write_page(ctx.room, "doc-3")
      insert_outcome(ctx.room.id, page_identifier: "doc-3", arm: "astra", trap_converged: true)
      insert_outcomes(ctx.room.id, "author_model", 19)
      {:ok, _} = Experiments.unblind(ctx.room.id, "author_model", unblind_attrs(ctx.jacob))

      assert %{experiment_id: "author_model", arm: "astra", trap_converged: true} =
               Experiments.page_arm(Experiments.page_arms(ctx.room.id), page)
    end

    test "of an unmatched Page is Bait against plain, blinded", ctx do
      page = write_page(ctx.room, "doc-4")
      insert_assignment(ctx.room.id, page_identifier: "someone-else", arm: "flash")
      insert_outcomes(ctx.room.id, "author_model", 20)
      {:ok, _} = Experiments.unblind(ctx.room.id, "author_model", unblind_attrs(ctx.jacob))

      assert Experiments.page_arm(Experiments.page_arms(ctx.room.id), page) == %{
               experiment_id: "bait_against_plain",
               experiment_unblinded: false,
               arm: nil,
               trap_converged: nil,
               deep_converged: nil
             }
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
      entry = entry()
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

    test "counts each Seat's current opinion of a Page, leaving out the admin's", ctx do
      {:ok, page} = Chronicle.write(ctx.room.id, entry())

      insert_outcome(ctx.room.id,
        page_id: page.id,
        page_identifier: page.id,
        experiment_id: "bait_against_plain",
        arm: "bait"
      )

      for attrs <- [
            %{seat_id: ctx.mara.id, label: "fair"},
            %{seat_id: ctx.mara.id, label: "too_harsh"},
            %{source: "admin", admin_id: Thereish.AdminFixtures.identity().id, label: "too_kind"}
          ] do
        {:ok, _} =
          Chronicle.record_fairness_tap(
            ctx.room.id,
            Map.merge(
              %{
                page_id: page.id,
                attempt_number: 1,
                bookends: ["lantern", "harbour"],
                bridges: ["cairn", "cairn"]
              },
              attrs
            )
          )
      end

      readout = Experiments.readout(ctx.room.id, "bait_against_plain")

      assert readout.bait.fairness_summary == "0 fair, 0 too kind, 1 too harsh"
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
