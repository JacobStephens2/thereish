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

  Everything that writes the harness's rows lives here: a Page's arm is
  assigned when the Author is asked for it, a closed Page's outcome is recorded
  from its Entry, and a Bookends tap is recorded and synced onto its Page's
  outcome. Like the Chronicle, the rows are tested against real Postgres
  through the Ecto sandbox.
  """

  import Ecto.Query

  require Logger

  alias Thereish.Chronicle.BookendsTap
  alias Thereish.Chronicle.Entry
  alias Thereish.Chronicle.ExperimentAssignment
  alias Thereish.Chronicle.ExperimentOutcome
  alias Thereish.Chronicle.ExperimentUnblinding
  alias Thereish.Chronicle.Page
  alias Thereish.Repo

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

  @author_model_arms [:flash, :astra]

  @author_model_experiment %{
    id: "author_model",
    name: "Author model: Flash against Astra",
    description:
      "Ticket 08: Tests whether Gemini 3.8 Flash or GPT-6 Astra writes bookends that yield higher meld rates, fewer attempts, and higher couple satisfaction taps.",
    sample_size: 20,
    arms: @author_model_arms,
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
  The experiment an arm belongs to: `flash` and `astra` are the Author-model
  experiment, and any other arm is Bait against plain.
  """
  @spec experiment_id_for_arm(atom()) :: String.t()
  def experiment_id_for_arm(arm) when arm in @author_model_arms,
    do: @author_model_experiment.id

  def experiment_id_for_arm(_arm), do: @first_experiment.id

  @doc """
  The arm a Page plays under when it has none of its own: Flash.
  """
  @spec default_arm() :: :flash
  def default_arm, do: :flash

  @doc """
  Assigns the next Page in a Room its Author-model arm, strictly alternating
  Flash and Astra from the Room's past assignments, and records the assignment
  blind.

  An assignment that cannot be read or written is logged and the Page plays
  under `default_arm/0`: a lost assignment must not stop the Author being asked.
  """
  @spec assign(Ecto.UUID.t() | String.t()) :: :flash | :astra
  def assign(room_id_or_slug) do
    room_id = resolve_room_id(room_id_or_slug)
    past_arms = room_id |> assignments(@author_model_experiment.id) |> Enum.map(& &1.arm)
    arm = next_arm(past_arms)

    %ExperimentAssignment{}
    |> ExperimentAssignment.changeset(%{
      room_id: room_id,
      page_identifier: "page-#{length(past_arms) + 1}",
      experiment_id: @author_model_experiment.id,
      arm: to_string(arm),
      chapter: "table",
      assigned_at: DateTime.utc_now()
    })
    |> Repo.insert!()

    arm
  rescue
    error ->
      Logger.error(
        "no experiment arm could be assigned, so the Page plays under #{default_arm()}: " <>
          Exception.message(error)
      )

      default_arm()
  end

  defp next_arm([]), do: default_arm()
  defp next_arm(past_arms), do: if(List.last(past_arms) == "flash", do: :astra, else: :flash)

  @doc """
  Records the experiment outcome of a closed Page from its Entry, once the
  Entry is written as `page`, under the experiment the Entry's arm belongs to.
  Links the Page to the oldest unlinked assignment of that experiment.

  An Entry with no arm has no experiment to record under, and is refused.
  """
  @spec record_outcome(Ecto.UUID.t() | String.t(), Page.t(), Entry.t()) ::
          {:ok, ExperimentOutcome.t()} | {:error, Ecto.Changeset.t()}
  def record_outcome(room_id, %Page{} = page, %Entry{arm: arm} = entry)
      when is_atom(arm) and not is_nil(arm) do
    room_id = resolve_room_id(room_id)
    experiment_id = experiment_id_for_arm(arm)

    closing_band = entry.closeness && to_string(Thereish.Ladder.read(entry.closeness).band)

    result =
      %ExperimentOutcome{}
      |> ExperimentOutcome.changeset(%{
        room_id: room_id,
        page_id: page.id,
        page_identifier: page.id,
        experiment_id: experiment_id,
        arm: to_string(arm),
        melded: entry.melded?,
        closeness: entry.closeness,
        closing_band: closing_band,
        attempts_count: length(entry.attempts),
        closed_because: to_string(entry.closed_because),
        trap_converged: any_verdict_meta?(entry, :trap_sprung),
        deep_converged: any_verdict_meta?(entry, :deep_convergence),
        taps: %{}
      })
      |> Repo.insert()

    from(a in ExperimentAssignment,
      where: a.room_id == ^room_id and is_nil(a.page_id) and a.experiment_id == ^experiment_id,
      order_by: [asc: a.inserted_at, asc: a.id],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> :ok
      assignment -> assignment |> Ecto.Changeset.change(page_id: page.id) |> Repo.update()
    end

    result
  end

  # Nothing has set these since ADR-0011; the columns stay until a schema
  # change removes them.
  defp any_verdict_meta?(%Entry{} = entry, key) do
    Enum.any?(entry.attempts, fn attempt ->
      Enum.any?(attempt.verdicts, &((&1.meta || %{})[key] == true))
    end)
  end

  @doc """
  Records a Bookends tap (flat, fine, or great) as an append-only event.
  Also syncs the tap into its Page's outcome's taps map, if that outcome
  exists. A tap that names no outcome updates none.
  """
  @spec record_bookends_tap(Ecto.UUID.t() | String.t(), map()) ::
          {:ok, BookendsTap.t()} | {:error, Ecto.Changeset.t()}
  def record_bookends_tap(room_id, attrs) do
    room_id = resolve_room_id(room_id)
    attrs = Map.put(attrs, :room_id, room_id)

    case %BookendsTap{} |> BookendsTap.changeset(attrs) |> Repo.insert() do
      {:ok, tap} ->
        sync_outcome_taps(room_id, tap)
        {:ok, tap}

      error ->
        error
    end
  end

  defp sync_outcome_taps(room_id, tap) do
    identifier = tap.page_identifier

    outcome =
      cond do
        identifier && tap.page_id ->
          Repo.one(
            from(o in ExperimentOutcome,
              where:
                o.room_id == ^room_id and
                  (o.page_identifier == ^identifier or o.page_id == ^tap.page_id),
              order_by: [desc: o.inserted_at],
              limit: 1
            )
          )

        identifier ->
          Repo.one(
            from(o in ExperimentOutcome,
              where: o.room_id == ^room_id and o.page_identifier == ^identifier,
              order_by: [desc: o.inserted_at],
              limit: 1
            )
          )

        tap.page_id ->
          Repo.one(
            from(o in ExperimentOutcome,
              where: o.room_id == ^room_id and o.page_id == ^tap.page_id,
              order_by: [desc: o.inserted_at],
              limit: 1
            )
          )

        true ->
          nil
      end

    # A tap with no outcome of its own is recorded alone rather than attached
    # to whichever Page happens to be latest.
    if outcome do
      updated_taps = Map.put(outcome.taps || %{}, to_string(tap.seat_id), to_string(tap.label))
      outcome |> Ecto.Changeset.change(taps: updated_taps) |> Repo.update()
    end
  end

  @doc """
  Returns all Bookends taps for a Room, oldest first.
  """
  @spec bookends_taps(Ecto.UUID.t() | String.t()) :: [BookendsTap.t()]
  def bookends_taps(room_id_or_slug) do
    room_id = resolve_room_id(room_id_or_slug)

    from(t in BookendsTap,
      where: t.room_id == ^room_id,
      order_by: [asc: t.inserted_at, asc: t.id]
    )
    |> Repo.all()
  end

  @doc """
  Returns all arm assignments for a Room, oldest first, of one experiment or
  of every experiment.
  """
  @spec assignments(Ecto.UUID.t() | String.t(), String.t() | nil) ::
          [ExperimentAssignment.t()]
  def assignments(room_id_or_slug, experiment_id \\ nil) do
    room_id = resolve_room_id(room_id_or_slug)

    from(a in ExperimentAssignment,
      where: a.room_id == ^room_id,
      order_by: [asc: a.assigned_at, asc: a.id]
    )
    |> of_experiment(experiment_id)
    |> Repo.all()
  end

  @doc """
  Returns all outcomes for a Room, oldest first, of one experiment or of every
  experiment.
  """
  @spec outcomes(Ecto.UUID.t() | String.t(), String.t() | nil) :: [ExperimentOutcome.t()]
  def outcomes(room_id_or_slug, experiment_id \\ nil) do
    room_id = resolve_room_id(room_id_or_slug)

    from(o in ExperimentOutcome,
      where: o.room_id == ^room_id,
      order_by: [asc: o.inserted_at, asc: o.id]
    )
    |> of_experiment(experiment_id)
    |> Repo.all()
  end

  @doc """
  Returns all unblindings for a Room, oldest first, of one experiment or of
  every experiment.
  """
  @spec unblindings(Ecto.UUID.t() | String.t(), String.t() | nil) ::
          [ExperimentUnblinding.t()]
  def unblindings(room_id_or_slug, experiment_id \\ nil) do
    room_id = resolve_room_id(room_id_or_slug)

    from(u in ExperimentUnblinding,
      where: u.room_id == ^room_id,
      order_by: [asc: u.unblinded_at, asc: u.id]
    )
    |> of_experiment(experiment_id)
    |> Repo.all()
  end

  @doc """
  Whether the experiment, or any experiment when none is named, has been
  deliberately unblinded in this Room.
  """
  @spec unblinded?(Ecto.UUID.t() | String.t(), String.t() | nil) :: boolean()
  def unblinded?(room_id_or_slug, experiment_id \\ nil) do
    room_id = resolve_room_id(room_id_or_slug)

    from(u in ExperimentUnblinding, where: u.room_id == ^room_id)
    |> of_experiment(experiment_id)
    |> Repo.exists?()
  end

  defp of_experiment(query, nil), do: query

  defp of_experiment(query, experiment_id),
    do: from(row in query, where: row.experiment_id == ^experiment_id)

  defp resolve_room_id(room_id_or_slug) do
    if is_binary(room_id_or_slug) and
         Regex.match?(
           ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
           room_id_or_slug
         ) do
      room_id_or_slug
    else
      Repo.get_by!(Thereish.Rooms.Room, slug: room_id_or_slug).id
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
