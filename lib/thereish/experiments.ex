defmodule Thereish.Experiments do
  @moduledoc """
  The A/B experiment harness (ticket 13, ADR-0004).

  The live Experiment is the Author model, Flash against Astra: each Page in a
  Room is assigned the next arm in strict alternation when the Author is asked
  for it. Bait against plain, ADR-0004's misdirection test, is retired, and its
  rows stay readable. Arm labels are blinded during play on stage and phones so
  neither player can play the label.

  Each Experiment declares its outcomes and its sample (20 Pages) up front.
  It stays blinded in a Room until the admin deliberately unblinds it there,
  which is refused until that sample of completed-Page outcomes is recorded.
  The readout is qualitative (streaks, preferences, attempts, closing bands
  and trap convergence) rather than p-values, because the sample is two
  people.

  The harness's rows are written and read here: a Page's assignment, a closed
  Page's outcome recorded from its Entry, a Bookends tap synced onto its
  Page's outcome, and an unblinding. `overview/0` gives the admin each Room's
  Experiments, their progress and, once unblinded, their readout.

  The readout's arithmetic is the pure `summarize/2`, tested without a
  database. Like the Chronicle, the rows are tested against real Postgres
  through the Ecto sandbox.
  """

  import Ecto.Query

  require Logger

  alias Thereish.Chronicle
  alias Thereish.Chronicle.BookendsTap
  alias Thereish.Chronicle.Entry
  alias Thereish.Chronicle.ExperimentAssignment
  alias Thereish.Chronicle.ExperimentOutcome
  alias Thereish.Chronicle.ExperimentUnblinding
  alias Thereish.Chronicle.Page
  alias Thereish.Repo
  alias Thereish.Rooms.Room

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
      Repo.get_by!(Room, slug: room_id_or_slug).id
    end
  end

  @doc """
  Blinded progress toward an experiment's declared sample in one Room. A nil
  experiment means the Room's active experiment.

  Counts recorded completed-Page outcomes across both arms combined. Assignments
  that never produced an outcome (still in play, or abandoned) do not count.
  """
  @spec progress(Ecto.UUID.t() | String.t(), String.t() | nil) :: %{
          recorded: non_neg_integer(),
          required: pos_integer(),
          ready?: boolean()
        }
  def progress(room_id_or_slug, experiment_id) do
    room_id = resolve_room_id(room_id_or_slug)
    experiment_id = experiment_id || active_experiment_id(room_id)
    required = definition(experiment_id).sample_size
    recorded = length(outcomes(room_id, experiment_id))

    %{recorded: recorded, required: required, ready?: recorded >= required}
  end

  @doc """
  Deliberately unblinds an experiment in one Room, recording when and by whom
  (`attrs`: `unblinded_at`, and optionally `seat_id` and `notes`). A nil
  experiment means the Room's active experiment.

  Refused until the Room has recorded the experiment's declared sample of
  completed-Page outcomes.
  """
  @spec unblind(Ecto.UUID.t() | String.t(), String.t() | nil, map()) ::
          {:ok, ExperimentUnblinding.t()}
          | {:error, :sample_incomplete | Ecto.Changeset.t()}
  def unblind(room_id_or_slug, experiment_id, attrs) do
    room_id = resolve_room_id(room_id_or_slug)
    experiment_id = experiment_id || active_experiment_id(room_id)

    if progress(room_id, experiment_id).ready? do
      %ExperimentUnblinding{}
      |> ExperimentUnblinding.changeset(
        Map.merge(attrs, %{room_id: room_id, experiment_id: experiment_id})
      )
      |> Repo.insert()
    else
      {:error, :sample_incomplete}
    end
  end

  # The experiment in view for a Room: that of its latest outcome, else of its
  # latest assignment, else the Author-model experiment.
  defp active_experiment_id(room_id) do
    latest_outcome = room_id |> outcomes() |> List.last()
    latest_assignment = room_id |> assignments() |> List.last()

    cond do
      latest_outcome -> latest_outcome.experiment_id
      latest_assignment -> latest_assignment.experiment_id
      true -> @author_model_experiment.id
    end
  end

  @doc """
  Every experiment of every Room that has an assignment, newest Room first:
  the Room, the experiment's definition, whether it is unblinded there, its
  progress, and its readout, which is nil while it is blinded.
  """
  @spec overview() :: [
          %{
            room: Room.t(),
            experiment: map(),
            unblinded?: boolean(),
            progress: map(),
            readout: map() | nil
          }
        ]
  def overview do
    for room <- experiment_rooms(), experiment_id <- experiment_ids(room.id) do
      unblinded? = unblinded?(room.id, experiment_id)

      %{
        room: room,
        experiment: definition(experiment_id),
        unblinded?: unblinded?,
        progress: progress(room.id, experiment_id),
        readout: if(unblinded?, do: readout(room.id, experiment_id))
      }
    end
  end

  defp experiment_rooms do
    room_ids = Repo.all(from(a in ExperimentAssignment, distinct: true, select: a.room_id))

    from(r in Room, where: r.id in ^room_ids, order_by: [desc: r.inserted_at])
    |> Repo.all()
  end

  # Experiment ids recorded in a Room, from assignments then outcomes.
  defp experiment_ids(room_id) do
    assignment_ids =
      from(a in ExperimentAssignment,
        where: a.room_id == ^room_id,
        distinct: true,
        select: a.experiment_id
      )
      |> Repo.all()

    outcome_ids =
      from(o in ExperimentOutcome,
        where: o.room_id == ^room_id,
        distinct: true,
        select: o.experiment_id
      )
      |> Repo.all()

    Enum.uniq(assignment_ids ++ outcome_ids)
  end

  @doc """
  The qualitative readout of an experiment in one Room, worked out by
  `summarize/2` from the Room's rows.

  A Room with no Author-model outcomes but some Bait-against-plain ones reads
  out Bait against plain instead.
  """
  @spec readout(Ecto.UUID.t() | String.t(), String.t()) :: map()
  def readout(room_id_or_slug, experiment_id) do
    room_id = resolve_room_id(room_id_or_slug)
    outcomes = outcomes(room_id, experiment_id)

    {experiment_id, outcomes} =
      with [] <- outcomes,
           "author_model" <- experiment_id,
           [_ | _] = bait_outcomes <- outcomes(room_id, @first_experiment.id) do
        {@first_experiment.id, bait_outcomes}
      else
        _ -> {experiment_id, outcomes}
      end

    summarize(experiment_id, %{
      outcomes: outcomes,
      fairness_taps: Chronicle.fairness_taps(room_id),
      overrules: Chronicle.overrules(room_id),
      views: Chronicle.page_views(room_id)
    })
  end

  @doc """
  Works out an experiment's qualitative readout from rows already in memory:
  its outcomes, oldest first, and the Room's fairness taps, overrules and
  Chronicle Page views. This is the readout's test surface; it touches no
  database.

  Returns `%{experiment: definition, <arm>: summary, summary_narrative: text}`.
  Every arm's summary carries its meld rate, longest and current meld streaks
  and mean attempts to meld. An Author-model arm adds its Bookends taps and
  closing bands; a Bait-against-plain arm adds its fairness taps, overrules
  and trap and deep convergence.

  Strictly avoids p-values or significance tests: the sample is two people.
  """
  @spec summarize(String.t(), %{
          outcomes: [ExperimentOutcome.t()],
          fairness_taps: [map()],
          overrules: [map()],
          views: [map()]
        }) :: map()
  def summarize("author_model", %{outcomes: outcomes}) do
    flash = summarize_author_arm(of_arm(outcomes, "flash"))
    astra = summarize_author_arm(of_arm(outcomes, "astra"))

    %{
      experiment: @author_model_experiment,
      flash: flash,
      astra: astra,
      summary_narrative:
        "Flash achieved a meld rate of #{flash.meld_rate} (best streak: #{flash.longest_meld_streak}, mean attempts: #{flash.mean_attempts_to_meld}) with #{flash.preferences_summary}. " <>
          "Astra achieved a meld rate of #{astra.meld_rate} (best streak: #{astra.longest_meld_streak}, mean attempts: #{astra.mean_attempts_to_meld}) with #{astra.preferences_summary}."
    }
  end

  def summarize("bait_against_plain", %{outcomes: outcomes} = rows) do
    bait_outcomes = of_arm(outcomes, "bait")
    plain_outcomes = of_arm(outcomes, "plain")
    bait_views = views_of(rows.views, bait_outcomes)
    plain_views = views_of(rows.views, plain_outcomes)

    # Feedback is read from the arm's Page views; a Room with none of them
    # falls back to matching the raw rows by the outcome's Page id.
    {bait_feedback, plain_feedback} =
      if bait_views != [] or plain_views != [] do
        {view_feedback(bait_views), view_feedback(plain_views)}
      else
        {row_feedback(rows, bait_outcomes), row_feedback(rows, plain_outcomes)}
      end

    bait = summarize_bait_arm(bait_outcomes, bait_feedback)
    plain = summarize_bait_arm(plain_outcomes, plain_feedback)

    %{
      experiment: @first_experiment,
      bait: bait,
      plain: plain,
      summary_narrative:
        "Bait-scored pages achieved a meld rate of #{bait.meld_rate} (best streak: #{bait.longest_meld_streak}, mean attempts: #{bait.mean_attempts_to_meld}) with #{bait.trap_sprung_count} traps sprung and #{bait.fairness_summary}. " <>
          "Plain pages achieved a meld rate of #{plain.meld_rate} (best streak: #{plain.longest_meld_streak}, mean attempts: #{plain.mean_attempts_to_meld}) with #{plain.fairness_summary} and #{plain.overrules_count} overrules."
    }
  end

  defp of_arm(outcomes, arm), do: Enum.filter(outcomes, &(&1.arm == arm))

  defp summarize_author_arm(outcomes) do
    taps =
      outcomes
      |> Enum.flat_map(&Map.values(&1.taps || %{}))
      |> Enum.frequencies_by(&to_string/1)

    great = Map.get(taps, "great", 0)
    fine = Map.get(taps, "fine", 0)
    flat = Map.get(taps, "flat", 0)

    outcomes
    |> meld_summary()
    |> Map.merge(%{
      preferences_summary: "#{great} great, #{fine} fine, #{flat} flat",
      great_count: great,
      fine_count: fine,
      flat_count: flat,
      closing_bands:
        outcomes |> Enum.map(& &1.closing_band) |> Enum.reject(&is_nil/1) |> Enum.frequencies(),
      bookends_taps: taps
    })
  end

  defp summarize_bait_arm(outcomes, {fairness_taps, overrules_count}) do
    labels = Enum.frequencies_by(fairness_taps, &to_string(&1.label))
    fair = Map.get(labels, "fair", 0)
    too_kind = Map.get(labels, "too_kind", 0)
    too_harsh = Map.get(labels, "too_harsh", 0)

    outcomes
    |> meld_summary()
    |> Map.merge(%{
      fairness_summary: "#{fair} fair, #{too_kind} too kind, #{too_harsh} too harsh",
      fair_count: fair,
      too_kind_count: too_kind,
      too_harsh_count: too_harsh,
      overrules_count: overrules_count,
      trap_sprung_count: Enum.count(outcomes, & &1.trap_converged),
      deep_convergence_count: Enum.count(outcomes, & &1.deep_converged)
    })
  end

  # The meld rate, streaks and mean attempts every arm's summary shares.
  defp meld_summary(outcomes) do
    pages = length(outcomes)
    melded_history = Enum.map(outcomes, & &1.melded)
    melded = Enum.count(melded_history, & &1)
    attempts = for o <- outcomes, o.melded, do: o.attempts_count
    meld_pct = if pages > 0, do: round(melded / pages * 100), else: 0

    %{
      pages_count: pages,
      melded_count: melded,
      meld_rate: "#{melded}/#{pages} (#{meld_pct}%)",
      longest_meld_streak: longest_streak(melded_history),
      current_meld_streak: melded_history |> Enum.reverse() |> Enum.take_while(& &1) |> length(),
      mean_attempts_to_meld:
        if(attempts == [], do: 0.0, else: Float.round(Enum.sum(attempts) / length(attempts), 1))
    }
  end

  defp longest_streak(melded_history) do
    melded_history
    |> Enum.chunk_by(& &1)
    |> Enum.filter(fn [melded? | _] -> melded? end)
    |> Enum.map(&length/1)
    |> Enum.max(fn -> 0 end)
  end

  # The Chronicle Page views an arm's outcomes name, by Page id or the
  # document's own id.
  defp views_of(views, outcomes) do
    identifiers =
      outcomes
      |> Enum.flat_map(&[to_string(&1.page_id), to_string(&1.page_identifier)])
      |> Enum.reject(&(&1 in ["", "nil"]))
      |> MapSet.new()

    Enum.filter(views, fn view ->
      to_string(view.id) in identifiers or to_string(view.document["id"]) in identifiers
    end)
  end

  defp view_feedback(views) do
    {Enum.flat_map(views, & &1.fairness_taps), views |> Enum.flat_map(& &1.overrules) |> length()}
  end

  defp row_feedback(rows, outcomes) do
    page_ids = for o <- outcomes, o.page_id, do: o.page_id

    {Enum.filter(rows.fairness_taps, &(&1.page_id in page_ids)),
     Enum.count(rows.overrules, &(&1.page_id in page_ids))}
  end
end
