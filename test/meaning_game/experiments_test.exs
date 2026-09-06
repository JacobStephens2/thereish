defmodule MeaningGame.ExperimentsTest do
  use ExUnit.Case, async: true

  alias MeaningGame.Experiments

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

  describe "arm assignment" do
    test "alternates arms within a room" do
      assert Experiments.assign_arm([]) == :flash
      assert Experiments.assign_arm([:flash]) == :astra
      assert Experiments.assign_arm([:flash, :astra]) == :flash
      assert Experiments.assign_arm([:flash, :astra, :flash]) == :astra

      assert Experiments.assign_arm(["flash"]) == :astra
      assert Experiments.assign_arm(["flash", "astra"]) == :flash
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
