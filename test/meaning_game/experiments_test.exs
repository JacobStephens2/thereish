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

  describe "stratified assignment" do
    test "balances assignment within each chapter stratum" do
      # If a chapter currently has more plain than bait, next must be bait
      past_in_chapter = [:plain, :plain, :bait]
      assert Experiments.assign_arm(past_in_chapter) == :bait

      # If a chapter currently has more bait than plain, next must be plain
      past_in_chapter = [:bait, :bait, :plain]
      assert Experiments.assign_arm(past_in_chapter) == :plain

      # If counts are equal, assigns either randomly
      past_in_chapter = [:bait, :plain]
      assert Experiments.assign_arm(past_in_chapter) in [:bait, :plain]
    end

    test "assignment is stratified by chapter and roughly balanced over many pages" do
      # Simulate 100 pages across 4 chapters
      chapters = ["harbour", "desert", "kitchen", "attic"]

      {assignments_by_chapter, all_assignments} =
        Enum.reduce(1..100, {%{}, []}, fn _i, {by_ch, all} ->
          chapter = Enum.random(chapters)
          chapter_history = Map.get(by_ch, chapter, [])
          arm = Experiments.assign_arm(chapter_history)

          {
            Map.put(by_ch, chapter, chapter_history ++ [arm]),
            all ++ [arm]
          }
        end)

      # In every chapter, the difference between arms is at most 1
      for {ch, arms} <- assignments_by_chapter do
        bait_count = Enum.count(arms, &(&1 == :bait))
        plain_count = Enum.count(arms, &(&1 == :plain))

        assert abs(bait_count - plain_count) <= 1,
               "Chapter #{ch} was not balanced: #{bait_count} bait vs #{plain_count} plain"
      end

      # Across all 100 pages, the total is roughly balanced
      total_bait = Enum.count(all_assignments, &(&1 == :bait))
      total_plain = Enum.count(all_assignments, &(&1 == :plain))
      assert abs(total_bait - total_plain) <= 4
    end
  end

  describe "arm scoring" do
    test "leaves standard Assayer verdict unchanged" do
      verdict = %{
        closeness: 100,
        reasoning: "Exact match on barbecue.",
        quip: "Two minds at the barbecue.",
        meta: %{}
      }

      scored = Experiments.score_verdict(verdict, %{}, :flash, ["barbecue", "barbecue"])
      assert scored.closeness == 100
      assert scored.reasoning == "Exact match on barbecue."
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
