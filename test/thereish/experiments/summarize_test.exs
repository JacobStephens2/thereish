defmodule Thereish.Experiments.SummarizeTest do
  @moduledoc """
  The readout's arithmetic at the `Experiments.summarize/2` seam: rows built
  in memory, no database.
  """
  use ExUnit.Case, async: true

  alias Thereish.Chronicle.Document
  alias Thereish.Chronicle.ExperimentOutcome
  alias Thereish.Chronicle.PageView
  alias Thereish.Experiments

  @no_rows %{outcomes: [], fairness_taps: [], overrules: [], views: []}

  defp outcome(arm, attrs) do
    struct!(
      %ExperimentOutcome{
        page_identifier: "page-#{System.unique_integer([:positive])}",
        arm: arm,
        melded: true,
        attempts_count: 1,
        trap_converged: false,
        deep_converged: false,
        taps: %{}
      },
      attrs
    )
  end

  # A participant's Opinion of the first Attempt of a Page.
  defp opinion(page_id, seat_id, label) do
    %{
      page_id: page_id,
      room_id: "room",
      attempt_number: 1,
      bookends: [page_id],
      source: "participant",
      seat_id: seat_id,
      label: label
    }
  end

  defp history(arm, melded_history) do
    Enum.map(melded_history, &outcome(arm, melded: &1))
  end

  defp summarize(experiment_id, rows),
    do: Experiments.summarize(experiment_id, Map.merge(@no_rows, rows))

  describe "both experiments" do
    test "a run of melds still going is the current streak as well as the longest" do
      readout =
        summarize("author_model", %{
          outcomes: history("flash", [true, true, false, true, true, true])
        })

      assert readout.flash.longest_meld_streak == 3
      assert readout.flash.current_meld_streak == 3
    end

    test "a miss ends the current streak but not the longest" do
      readout =
        summarize("bait_against_plain", %{outcomes: history("bait", [true, true, true, false])})

      assert readout.bait.longest_meld_streak == 3
      assert readout.bait.current_meld_streak == 0
    end

    test "an arm with no Pages reads as nothing played rather than dividing by zero" do
      for {experiment_id, arms} <- [
            {"author_model", [:flash, :astra]},
            {"bait_against_plain", [:bait, :plain]}
          ],
          arm <- arms do
        summary = Map.fetch!(summarize(experiment_id, %{}), arm)

        assert summary.pages_count == 0
        assert summary.meld_rate == "0/0 (0%)"
        assert summary.longest_meld_streak == 0
        assert summary.current_meld_streak == 0
        assert summary.mean_attempts_to_meld == 0.0
      end
    end

    test "mean attempts counts only the Pages that melded" do
      outcomes = [
        outcome("flash", melded: true, attempts_count: 1),
        outcome("flash", melded: true, attempts_count: 2),
        outcome("flash", melded: false, attempts_count: 3)
      ]

      assert summarize("author_model", %{outcomes: outcomes}).flash.mean_attempts_to_meld == 1.5
    end

    test "reports streaks and preferences rather than p-values" do
      for experiment_id <- ["author_model", "bait_against_plain"] do
        readout = summarize(experiment_id, %{})

        assert is_binary(readout.summary_narrative)
        refute Map.has_key?(readout, :p_value)
        refute Map.has_key?(readout, :t_stat)
        refute Map.has_key?(readout, :chi_squared)
      end
    end
  end

  describe "the Author-model experiment" do
    test "summarizes Flash and Astra by meld rate, Bookends taps and closing bands" do
      outcomes =
        history("flash", [true, true, false, true]) ++
          [
            outcome("astra",
              closing_band: "meld",
              taps: %{"seat-a" => "great", "seat-b" => "flat"}
            ),
            outcome("astra", closing_band: "deep_meld", taps: %{"seat-a" => "great"}),
            outcome("astra", closing_band: "meld", taps: %{"seat-b" => "fine"}),
            outcome("astra", closing_band: nil)
          ]

      readout = summarize("author_model", %{outcomes: outcomes})

      assert readout.experiment == Experiments.definition("author_model")
      assert readout.flash.pages_count == 4
      assert readout.flash.melded_count == 3
      assert readout.flash.meld_rate == "3/4 (75%)"
      assert readout.flash.longest_meld_streak == 2
      assert readout.astra.meld_rate == "4/4 (100%)"
      assert readout.astra.longest_meld_streak == 4

      assert readout.astra.great_count == 2
      assert readout.astra.fine_count == 1
      assert readout.astra.flat_count == 1
      assert readout.astra.preferences_summary == "2 great, 1 fine, 1 flat"
      assert readout.astra.bookends_taps == %{"great" => 2, "fine" => 1, "flat" => 1}
      assert readout.astra.closing_bands == %{"meld" => 2, "deep_meld" => 1}
      assert readout.flash.preferences_summary == "0 great, 0 fine, 0 flat"

      assert readout.summary_narrative =~
               "Flash achieved a meld rate of 3/4 (75%) (best streak: 2"

      assert readout.summary_narrative =~ "Astra achieved a meld rate of 4/4 (100%)"
    end

    test "ignores the fairness taps, overrules and views it is handed" do
      outcomes = [outcome("flash", page_identifier: "P001")]
      rows = %{outcomes: outcomes}

      with_feedback = %{
        outcomes: outcomes,
        fairness_taps: [%{page_id: "P001", label: "fair"}],
        overrules: [%{page_id: "P001"}],
        views: [%PageView{id: "P001", document: %Document{}, fairness_taps: [], overrules: []}]
      }

      assert summarize("author_model", with_feedback) == summarize("author_model", rows)
    end
  end

  describe "the channel experiment" do
    test "summarizes the nudging Pages against the quiet ones by meld rate and attempts" do
      outcomes =
        [
          outcome("nudge_on", melded: true, attempts_count: 3),
          outcome("nudge_on", melded: false, attempts_count: 3),
          outcome("nudge_on", melded: true, attempts_count: 2, closing_band: "meld"),
          outcome("nudge_off", melded: true, attempts_count: 1, taps: %{"seat-a" => "fine"}),
          outcome("nudge_off", melded: true, attempts_count: 2, closing_band: "deep_meld")
        ]

      readout = summarize("channel", %{outcomes: outcomes})

      assert readout.experiment == Experiments.definition("channel")
      assert readout.nudge_on.meld_rate == "2/3 (67%)"
      assert readout.nudge_on.mean_attempts_to_meld == 2.5
      assert readout.nudge_on.closing_bands == %{"meld" => 1}
      assert readout.nudge_off.meld_rate == "2/2 (100%)"
      assert readout.nudge_off.mean_attempts_to_meld == 1.5
      assert readout.nudge_off.preferences_summary == "0 great, 1 fine, 0 flat"

      assert readout.summary_narrative =~
               "Pages with a Nudge achieved a meld rate of 2/3 (67%)"

      assert readout.summary_narrative =~ "Pages without one achieved a meld rate of 2/2 (100%)"
    end

    test "counts no Nudges, Calls or Reactions anywhere in the readout" do
      readout = summarize("channel", %{outcomes: history("nudge_on", [true, false])})

      refute Map.has_key?(readout.nudge_on, :nudges_count)
      refute Map.has_key?(readout.nudge_on, :calls_count)
      refute Map.has_key?(readout.nudge_on, :reactions_count)
      refute Map.has_key?(readout, :p_value)
    end

    test "an arm with no Pages reads as nothing played" do
      readout = summarize("channel", %{})

      for arm <- [:nudge_on, :nudge_off] do
        summary = Map.fetch!(readout, arm)

        assert summary.pages_count == 0
        assert summary.meld_rate == "0/0 (0%)"
        assert summary.mean_attempts_to_meld == 0.0
      end
    end
  end

  describe "the Bait-against-plain experiment" do
    test "summarizes each arm's traps, deep convergence, fairness taps and overrules from its Pages' views" do
      bait = [
        outcome("bait", page_id: "page-1", trap_converged: true, deep_converged: true),
        outcome("bait", page_id: "page-2", melded: false, trap_converged: true)
      ]

      plain = [outcome("plain", page_identifier: "doc-3")]

      views = [
        %{
          id: "page-1",
          document: %Document{identifier: "doc-1"},
          fairness_taps: [
            opinion("page-1", "mara", "fair"),
            opinion("page-1", "jacob", "too_harsh")
          ],
          overrules: []
        },
        %{
          id: "page-2",
          document: %Document{identifier: "doc-2"},
          fairness_taps: [opinion("page-2", "mara", "fair")],
          overrules: []
        },
        %{
          id: "page-3",
          document: %Document{identifier: "doc-3"},
          fairness_taps: [opinion("page-3", "mara", "too_kind")],
          overrules: [%{id: 1}, %{id: 2}]
        },
        %{
          id: "page-4",
          document: %Document{identifier: "doc-4"},
          fairness_taps: [opinion("page-4", "mara", "fair")],
          overrules: [%{id: 3}]
        }
      ]

      readout = summarize("bait_against_plain", %{outcomes: bait ++ plain, views: views})

      assert readout.experiment == Experiments.definition("bait_against_plain")
      assert readout.bait.meld_rate == "1/2 (50%)"
      assert readout.bait.trap_sprung_count == 2
      assert readout.bait.deep_convergence_count == 1
      assert readout.bait.fair_count == 2
      assert readout.bait.too_harsh_count == 1
      assert readout.bait.too_kind_count == 0
      assert readout.bait.fairness_summary == "2 fair, 0 too kind, 1 too harsh"
      assert readout.bait.overrules_count == 0

      assert readout.plain.meld_rate == "1/1 (100%)"
      assert readout.plain.too_kind_count == 1
      assert readout.plain.overrules_count == 2

      assert readout.summary_narrative =~ "Bait-scored pages achieved a meld rate of 1/2 (50%)"

      assert readout.summary_narrative =~
               "with 2 traps sprung and 2 fair, 0 too kind, 1 too harsh"

      assert readout.summary_narrative =~ "Plain pages achieved a meld rate of 1/1 (100%)"
      assert readout.summary_narrative =~ "and 2 overrules"
    end

    test "with no Page views, reads fairness taps and overrules by the outcome's Page id" do
      outcomes = [outcome("bait", page_id: "page-1"), outcome("plain", page_id: "page-2")]

      fairness_taps = [
        opinion("page-1", "mara", "fair"),
        opinion("page-2", "mara", "too_kind"),
        opinion("page-2", "jacob", "too_kind"),
        opinion("elsewhere", "mara", "too_harsh")
      ]

      overrules = [%{page_id: "page-2"}, %{page_id: "elsewhere"}]

      readout =
        summarize("bait_against_plain", %{
          outcomes: outcomes,
          fairness_taps: fairness_taps,
          overrules: overrules
        })

      assert readout.bait.fair_count == 1
      assert readout.bait.overrules_count == 0
      assert readout.plain.too_kind_count == 2
      assert readout.plain.overrules_count == 1
      assert readout.bait.too_harsh_count + readout.plain.too_harsh_count == 0
    end

    test "reads out an experiment it does not recognise, as it reads any non-Author-model arm" do
      readout = summarize("unrecognised", %{outcomes: history("bait", [true, false])})

      assert readout.experiment.id == "bait_against_plain"
      assert readout.bait.meld_rate == "1/2 (50%)"
    end
  end
end
