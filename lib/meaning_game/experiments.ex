defmodule MeaningGame.Experiments do
  @moduledoc """
  The A/B experiment harness (ticket 13, ADR-0004).

  Every Page is randomly assigned to an arm, stratified by Chapter so one arm
  does not collect all the easy meaning-spaces. Arm labels are blinded during play
  on stage and phones so neither player can play the label.

  The first experiment is Bait-scored Pages against plain ones, testing ADR-0004's
  misdirection decision.

  Declared outcomes and sample size (20 Pages) are fixed up front before the first
  Page is played. The readout is qualitative (streaks, fairness preferences,
  attempts, and trap convergence) rather than p-values because the sample is two
  people.
  """

  @first_experiment %{
    id: "bait_against_plain",
    name: "Bait against plain",
    description:
      "ADR-0004: Tests whether Bait-scored Pages (penalizing obvious traps with the lowest meld rung, rewarding deep bridges) improve couple play over plain semantic grading.",
    sample_size: 20,
    arms: [:bait, :plain],
    declared_outcomes: [
      :meld_rate,
      :attempts_to_meld,
      :fairness_preference,
      :overrule_rate,
      :trap_convergence
    ]
  }

  @doc """
  Returns the declared experiment definition.
  """
  @spec definition(atom() | String.t()) :: map()
  def definition(:bait_against_plain), do: @first_experiment
  def definition("bait_against_plain"), do: @first_experiment
  def definition(_), do: @first_experiment

  @doc """
  Stratified arm assignment for a given chapter stratum.

  Balances arms within each chapter: if one arm has fewer pages in this chapter,
  it is assigned next. If balanced, randomly picks with 50/50 probability.
  """
  @spec assign_arm([atom() | String.t()]) :: :bait | :plain
  def assign_arm(chapter_history) when is_list(chapter_history) do
    normalized =
      Enum.map(chapter_history, fn
        :bait -> :bait
        "bait" -> :bait
        _ -> :plain
      end)

    bait_count = Enum.count(normalized, &(&1 == :bait))
    plain_count = Enum.count(normalized, &(&1 == :plain))

    cond do
      bait_count < plain_count -> :bait
      plain_count < bait_count -> :plain
      true -> Enum.random([:bait, :plain])
    end
  end

  @doc """
  Applies experimental arm grading rules to a verdict.

  In the :plain arm, the Assayer's standard grading is preserved.
  In the :bait arm:
  - Converging on the planted bait is scored as a Meld on the lowest rung (75).
  - Converging on a deep bridge is rewarded with the top rung (95+).
  - Other responses keep standard Assayer closeness.

  Note: To preserve blinding during active play, arm labels and trap notices
  are never written into verdict.reasoning (which is visible on phones and stage).
  Trap and deep convergence flags are recorded in verdict.meta for Chronicle
  unblinded viewing.
  Joint player overrules are never overwritten (ADR-0006, design law 3).
  """
  @spec apply_arm_closeness(map(), map(), :bait | :plain | String.t(), [String.t()]) :: map()
  def apply_arm_closeness(verdict, _page, arm, _bridges) when arm in [:plain, "plain"] do
    verdict
  end

  def apply_arm_closeness(verdict, page, arm, bridges) when arm in [:bait, "bait"] do
    if Map.get(verdict, :overruled?, false) or Map.get(verdict.meta || %{}, :overruled, false) do
      verdict
    else
      [left, right] =
        case bridges do
          [l, r | _] -> [normalize_word(l), normalize_word(r)]
          [l] -> [normalize_word(l), ""]
          _ -> ["", ""]
        end

      bait = normalize_word(page[:bait] || page["bait"])

      deep_bridges =
        (page[:deep_bridges] || page["deep_bridges"] || [])
        |> Enum.map(&normalize_word/1)

      cond do
        left != "" and left == bait and right == bait ->
          # Converged on the bait trap: a Meld on the lowest rung (75) per ADR-0004.
          # Blinding: Do NOT leak arm or "bait trap" into player-visible reasoning during play!
          meta = Map.put(verdict.meta || %{}, :trap_sprung, true)

          %{
            verdict
            | closeness: 75,
              meta: meta
          }

        left != "" and left in deep_bridges and right in deep_bridges ->
          # Converged on deep bridges: top rung (:deep_meld)
          meta = Map.put(verdict.meta || %{}, :deep_convergence, true)

          %{
            verdict
            | closeness: max(verdict.closeness || 0, 95),
              meta: meta
          }

        true ->
          verdict
      end
    end
  end

  @doc """
  Backwards-compatible alias for `apply_arm_closeness/4`.
  """
  @spec score_verdict(map(), map(), :bait | :plain | String.t(), [String.t()]) :: map()
  def score_verdict(verdict, page, arm, bridges),
    do: apply_arm_closeness(verdict, page, arm, bridges)

  @doc """
  Computes a qualitative readout comparing the arms.

  Strictly avoids p-values or significance tests, focusing on streaks,
  fairness preferences, attempts to meld, and trap rates for the two players.
  """
  @spec qualitative_readout(map()) :: map()
  def qualitative_readout(data) when is_map(data) do
    bait_data = Map.get(data, :bait) || Map.get(data, "bait") || %{}
    plain_data = Map.get(data, :plain) || Map.get(data, "plain") || %{}

    bait_summary = summarize_arm(bait_data)
    plain_summary = summarize_arm(plain_data)

    narrative = generate_narrative(bait_summary, plain_summary)

    %{
      experiment: @first_experiment,
      bait: bait_summary,
      plain: plain_summary,
      summary_narrative: narrative
    }
  end

  defp summarize_arm(arm_data) do
    pages = Map.get(arm_data, :pages_count, 0)
    melded = Map.get(arm_data, :melded_count, 0)
    melded_history = Map.get(arm_data, :melded_history, [])
    streaks = calculate_streaks(melded_history)
    attempts = Map.get(arm_data, :attempts_to_meld, [])
    taps = Map.get(arm_data, :fairness_taps, %{})
    overrules = Map.get(arm_data, :overrules_count, 0)
    traps = Map.get(arm_data, :trap_sprung_count, 0)
    deep = Map.get(arm_data, :deep_convergence_count, 0)

    meld_pct = if pages > 0, do: round(melded / pages * 100), else: 0
    meld_rate_str = "#{melded}/#{pages} (#{meld_pct}%)"

    mean_attempts =
      if attempts != [] do
        Float.round(Enum.sum(attempts) / length(attempts), 1)
      else
        0.0
      end

    fair_count = Map.get(taps, "fair", 0) + Map.get(taps, :fair, 0)
    kind_count = Map.get(taps, "too_kind", 0) + Map.get(taps, :too_kind, 0)
    harsh_count = Map.get(taps, "too_harsh", 0) + Map.get(taps, :too_harsh, 0)

    fairness_str = "#{fair_count} fair, #{kind_count} too kind, #{harsh_count} too harsh"

    %{
      pages_count: pages,
      melded_count: melded,
      meld_rate: meld_rate_str,
      longest_meld_streak: streaks.longest_meld_streak,
      current_meld_streak: streaks.current_meld_streak,
      mean_attempts_to_meld: mean_attempts,
      fairness_summary: fairness_str,
      fair_count: fair_count,
      too_kind_count: kind_count,
      too_harsh_count: harsh_count,
      overrules_count: overrules,
      trap_sprung_count: traps,
      deep_convergence_count: deep
    }
  end

  @doc """
  Calculates longest and current meld streaks from chronological history of meld results.
  """
  @spec calculate_streaks([boolean()]) :: %{
          longest_meld_streak: non_neg_integer(),
          current_meld_streak: non_neg_integer()
        }
  def calculate_streaks(melded_history) when is_list(melded_history) do
    longest =
      melded_history
      |> Enum.chunk_by(& &1)
      |> Enum.filter(fn [first | _] -> first == true end)
      |> Enum.map(&length/1)
      |> Enum.max(fn -> 0 end)

    current =
      melded_history
      |> Enum.reverse()
      |> Enum.take_while(& &1)
      |> length()

    %{longest_meld_streak: longest, current_meld_streak: current}
  end

  defp generate_narrative(bait, plain) do
    "Bait-scored pages achieved a meld rate of #{bait.meld_rate} (best streak: #{bait.longest_meld_streak}, mean attempts: #{bait.mean_attempts_to_meld}) with #{bait.trap_sprung_count} traps sprung and #{bait.fairness_summary}. " <>
      "Plain pages achieved a meld rate of #{plain.meld_rate} (best streak: #{plain.longest_meld_streak}, mean attempts: #{plain.mean_attempts_to_meld}) with #{plain.fairness_summary} and #{plain.overrules_count} overrules."
  end

  defp normalize_word(nil), do: ""

  defp normalize_word(word) when is_binary(word) do
    MeaningGame.Steward.Precedent.normalize(word)
  end
end
