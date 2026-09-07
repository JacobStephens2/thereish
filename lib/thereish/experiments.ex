defmodule Thereish.Experiments do
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

  @author_model_experiment %{
    id: "author_model",
    name: "Author model: Flash against Astra",
    description:
      "Ticket 08: Tests whether Gemini 3.8 Flash or GPT-6 Astra writes bookends that yield higher meld rates, fewer attempts, and higher couple satisfaction taps.",
    sample_size: 20,
    arms: [:flash, :astra],
    declared_outcomes: [
      :meld_rate,
      :attempts_to_meld,
      :bookends_preferences,
      :closing_band
    ]
  }

  @doc """
  Returns the declared experiment definition.
  """
  @spec definition(atom() | String.t()) :: map()
  def definition(:bait_against_plain), do: @first_experiment
  def definition("bait_against_plain"), do: @first_experiment
  def definition(:author_model), do: @author_model_experiment
  def definition("author_model"), do: @author_model_experiment
  def definition(_), do: @author_model_experiment

  @doc """
  Assigns arm for the room, strictly alternating arms (:flash then :astra).
  """
  @spec assign_arm([atom() | String.t()]) :: :flash | :astra
  def assign_arm([]), do: :flash

  def assign_arm(room_history) when is_list(room_history) do
    case List.last(room_history) do
      arm when arm in [:flash, "flash"] -> :astra
      _ -> :flash
    end
  end

  @doc """
  Computes a qualitative readout comparing the arms.

  Strictly avoids p-values or significance tests, focusing on streaks,
  preferences, attempts to meld, and closing bands for the two players.
  """
  @spec qualitative_readout(map()) :: map()
  def qualitative_readout(data) when is_map(data) do
    if is_author_model_data?(data) do
      readout_author_model(data)
    else
      readout_bait_against_plain(data)
    end
  end

  defp is_author_model_data?(data) do
    Map.has_key?(data, :flash) or Map.has_key?(data, "flash") or
      Map.has_key?(data, :astra) or Map.has_key?(data, "astra")
  end

  defp readout_author_model(data) do
    flash_data = Map.get(data, :flash) || Map.get(data, "flash") || %{}
    astra_data = Map.get(data, :astra) || Map.get(data, "astra") || %{}

    flash_summary = summarize_author_arm(flash_data)
    astra_summary = summarize_author_arm(astra_data)

    narrative = generate_author_narrative(flash_summary, astra_summary)

    %{
      experiment: @author_model_experiment,
      flash: flash_summary,
      astra: astra_summary,
      summary_narrative: narrative
    }
  end

  defp summarize_author_arm(arm_data) do
    pages = Map.get(arm_data, :pages_count, 0)
    melded = Map.get(arm_data, :melded_count, 0)
    melded_history = Map.get(arm_data, :melded_history, [])
    streaks = calculate_streaks(melded_history)
    attempts = Map.get(arm_data, :attempts_to_meld, [])
    taps = Map.get(arm_data, :bookends_taps, %{})
    closing_bands = Map.get(arm_data, :closing_bands, %{})

    meld_pct = if pages > 0, do: round(melded / pages * 100), else: 0
    meld_rate_str = "#{melded}/#{pages} (#{meld_pct}%)"

    mean_attempts =
      if attempts != [] do
        Float.round(Enum.sum(attempts) / length(attempts), 1)
      else
        0.0
      end

    great_count = Map.get(taps, "great", 0) + Map.get(taps, :great, 0)
    fine_count = Map.get(taps, "fine", 0) + Map.get(taps, :fine, 0)
    flat_count = Map.get(taps, "flat", 0) + Map.get(taps, :flat, 0)

    preferences_str = "#{great_count} great, #{fine_count} fine, #{flat_count} flat"

    %{
      pages_count: pages,
      melded_count: melded,
      meld_rate: meld_rate_str,
      longest_meld_streak: streaks.longest_meld_streak,
      current_meld_streak: streaks.current_meld_streak,
      mean_attempts_to_meld: mean_attempts,
      preferences_summary: preferences_str,
      great_count: great_count,
      fine_count: fine_count,
      flat_count: flat_count,
      closing_bands: closing_bands,
      bookends_taps: taps
    }
  end

  defp generate_author_narrative(flash, astra) do
    "Flash achieved a meld rate of #{flash.meld_rate} (best streak: #{flash.longest_meld_streak}, mean attempts: #{flash.mean_attempts_to_meld}) with #{flash.preferences_summary}. " <>
      "Astra achieved a meld rate of #{astra.meld_rate} (best streak: #{astra.longest_meld_streak}, mean attempts: #{astra.mean_attempts_to_meld}) with #{astra.preferences_summary}."
  end

  defp readout_bait_against_plain(data) do
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
end
