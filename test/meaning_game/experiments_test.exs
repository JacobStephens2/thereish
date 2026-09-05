defmodule MeaningGame.ExperimentsTest do
  use ExUnit.Case, async: true

  alias MeaningGame.Experiments

  describe "experiment declaration" do
    test "declares bait_against_plain experiment with sample size and outcomes fixed up front" do
      exp = Experiments.definition(:bait_against_plain)

      assert exp.id == "bait_against_plain"
      assert exp.name == "Bait against plain"
      assert exp.sample_size == 20
      assert exp.arms == [:bait, :plain]
      assert :meld_rate in exp.declared_outcomes
      assert :attempts_to_meld in exp.declared_outcomes
      assert :fairness_preference in exp.declared_outcomes
      assert :overrule_rate in exp.declared_outcomes
      assert :trap_convergence in exp.declared_outcomes
    end
  end

  describe "arm assignment" do
    test "is fixed to :flash until Issue 08" do
      assert Experiments.assign_arm([]) == :flash
      assert Experiments.assign_arm([:bait]) == :flash
      assert Experiments.assign_arm([:plain]) == :flash
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
  end
end
