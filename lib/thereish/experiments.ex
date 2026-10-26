defmodule Thereish.Experiments do
  @moduledoc """
  Experiment definitions, alternating assignments and qualitative readouts.

  Two Experiments are live. The Author model, Flash against Astra, decides
  which model writes the Page's Bookends; the channel, Nudge on against off,
  decides whether the Page has a Nudge in it at all (ADR-0020). Each Page is
  assigned an Arm of both when the Author is asked for it, unless its Room has
  Nudges off and takes no channel Arm. Each Experiment alternates
  strictly on its own rows, so the two never line up and neither confounds the
  other. Assignment is deterministic, with no randomization or Chapter
  stratification. Bait against plain, ADR-0004's misdirection test, is retired,
  and its rows stay readable.

  This module owns the harness: the Experiments' definitions, each declaring
  its outcomes and its sample (20 Pages) up front; a Page's Assignment; a
  closed Page's outcome recorded from its Entry and linked to the Entry's own
  Assignment; a Bookends tap synced onto
  its Page's outcome; each Experiment's blinded progress toward its sample;
  its unblinding, which the admin asks for deliberately and which is refused
  until the sample is recorded; the admin's `overview/0`; and the readout.

  It also owns Page blinding. Arm labels stay hidden during play on stage and
  phones, and in the Chronicle, so neither player can play the label: the
  Chronicle's Page views take their experiment fields from `page_arms/1` and
  `page_arm/2`, which show an Arm only once its Experiment is unblinded in
  the Room.

  The readout is qualitative (streaks, preferences, attempts, closing bands
  and trap convergence) rather than p-values, because the sample is two
  people. Its arithmetic is the pure `summarize/2`, tested without a
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
  alias Thereish.Chronicle.Opinion
  alias Thereish.Chronicle.Page
  alias Thereish.Experiments.Assignment
  alias Thereish.Repo
  alias Thereish.Rooms.Room

  @bait_against_plain_id "bait_against_plain"
  @author_model_id "author_model"
  @channel_id "channel"

  @bait_against_plain_experiment %{
    id: @bait_against_plain_id,
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
    id: @author_model_id,
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

  @channel_experiment %{
    id: @channel_id,
    name: "The channel: Nudge on against off",
    description:
      "ADR-0020: Tests whether one spendable, public, burned word between Seats makes an Attempt harder and a Page better — read from the meld rate, the attempts it took, where the Page closed, and the tap on the Bookends.",
    sample_size: 20,
    arms: [:nudge_on, :nudge_off],
    declared_outcomes: [
      :meld_rate,
      :attempts_to_meld,
      :closing_band,
      :bookends_preferences
    ]
  }

  @doc """
  Returns the declared experiment definition.

  An id nothing declares raises rather than answering with whichever
  Experiment happens to be live: a readout filed under a name the harness does
  not know is a measurement of nothing.
  """
  @spec definition(atom() | String.t()) :: map()
  def definition(:bait_against_plain), do: @bait_against_plain_experiment
  def definition(@bait_against_plain_id), do: @bait_against_plain_experiment
  def definition(:author_model), do: @author_model_experiment
  def definition(@author_model_id), do: @author_model_experiment
  def definition(:channel), do: @channel_experiment
  def definition(@channel_id), do: @channel_experiment

  def definition(experiment_id),
    do: raise(ArgumentError, "no Experiment is declared as #{inspect(experiment_id)}")

  # The Experiments a Page is assigned an Arm of when the Author is asked for
  # it, the Author model first because its Arm is the one the Room is handed
  # and the one the book files a Page under.
  @live_experiments [@author_model_experiment, @channel_experiment]

  # The Arm a Page plays under when it has no Assignment of its own: Flash,
  # under the Author-model Experiment, with no row to link.
  @default_assignment %Assignment{id: nil, experiment_id: @author_model_id, arm: :flash}

  @doc """
  Assigns the next Page in a Room an Arm of every eligible live Experiment, each
  strictly alternating from that Experiment's own past rows in the Room,
  records a row for each blind, and answers the Author-model one as the Page's
  Assignment with the rest beside it (`Assignment.arm/2`).

  A Room with Nudges off gets no channel Assignment: its Pages advance
  neither that Experiment's alternation nor its sample (ADR-0020).

  When no row can be read or written, that is logged and the Page plays under
  the default Arm, Flash, with no row and no other Experiment: a lost row must
  not stop the Author being asked, and a Page whose Arms are unknown is a Page
  that measures nothing rather than one that plays a guess.
  """
  @spec assign(Ecto.UUID.t() | String.t()) :: Assignment.t()
  def assign(room_id_or_slug) do
    room_id = resolve_room_id(room_id_or_slug)
    room = Repo.get!(Room, room_id)
    past = Enum.group_by(assignments(room_id), & &1.experiment_id, & &1.arm)
    # Every row names the Page the same way, so a Page's Arms read as one Page.
    identifier = "page-#{length(Map.get(past, @author_model_id, [])) + 1}"
    at = DateTime.utc_now()

    made =
      for experiment <- @live_experiments,
          experiment.id != @channel_id or room.nudges do
        %Assignment{
          id: Ecto.UUID.generate(),
          experiment_id: experiment.id,
          arm: next_arm(experiment, Map.get(past, experiment.id, []))
        }
      end

    # One read and one write however many Experiments are live: the Room asks
    # for this in the seconds between the last Give and the Author's answer,
    # and every row still passes the changeset's gate on the way in.
    {_count, _} =
      Repo.insert_all(
        ExperimentAssignment,
        Enum.map(made, &assignment_row(&1, room_id, identifier, at))
      )

    [author | rest] = made
    %{author | also: rest}
  rescue
    error ->
      Logger.error(
        "no experiment arm could be assigned, so the Page plays under #{@default_assignment.arm}: " <>
          Exception.message(error)
      )

      @default_assignment
  end

  # One row for `Repo.insert_all`, built through the changeset so that an Arm
  # the schema does not know raises here rather than reaching Postgres.
  defp assignment_row(%Assignment{} = assignment, room_id, identifier, at) do
    %ExperimentAssignment{}
    |> ExperimentAssignment.changeset(%{
      room_id: room_id,
      page_identifier: identifier,
      experiment_id: assignment.experiment_id,
      arm: to_string(assignment.arm),
      chapter: "table",
      assigned_at: at
    })
    |> Ecto.Changeset.apply_action!(:insert)
    |> Map.take([:room_id, :page_identifier, :experiment_id, :arm, :chapter, :assigned_at])
    |> Map.merge(%{id: assignment.id, inserted_at: at})
  end

  # The Arm after the last one this Room recorded of that Experiment, and the
  # first Arm when it has recorded none. Each Experiment declares two.
  defp next_arm(experiment, past_arms) do
    [first, second] = experiment.arms

    if List.last(past_arms) == to_string(first), do: second, else: first
  end

  @doc """
  Records the experiment outcome of a closed Page from its Entry, once the
  Entry is written as `page`, under the Experiment and Arm of the Entry's
  Assignment, and links the Page to that Assignment's own row, unless the row
  is already linked.

  A Page played under more than one Experiment is recorded under each of them,
  one row per Arm it carried, and answers with the outcome of the Assignment
  the Room was handed.

  An Entry with no Assignment is recorded under the default Arm and links no
  row, as does an Assignment that has no row.
  """
  @spec record_outcome(Ecto.UUID.t() | String.t(), Page.t(), Entry.t()) ::
          {:ok, ExperimentOutcome.t()} | {:error, Ecto.Changeset.t()}
  def record_outcome(room_id, %Page{} = page, %Entry{} = entry) do
    room_id = resolve_room_id(room_id)
    assignment = entry.assignment || @default_assignment

    arms = [assignment | assignment.also]

    [outcome | _] = for one <- arms, do: insert_outcome(room_id, page, entry, one)

    # A Page with no outcome links no row.
    with {:ok, _} <- outcome, do: link_assignments(room_id, arms, page)

    outcome
  end

  defp insert_outcome(room_id, %Page{} = page, %Entry{} = entry, %Assignment{} = assignment) do
    closing_band = entry.closeness && to_string(Thereish.Ladder.read(entry.closeness).band)

    %ExperimentOutcome{}
    |> ExperimentOutcome.changeset(%{
      room_id: room_id,
      page_id: page.id,
      page_identifier: page.id,
      experiment_id: assignment.experiment_id,
      arm: to_string(assignment.arm),
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
  end

  # Every row of the Page's Assignments at once, in one write. An Assignment
  # with no row of its own links nothing, and a row already linked to another
  # Page is left alone.
  defp link_assignments(room_id, assignments, page) do
    ids = for %Assignment{id: id} <- assignments, id != nil, do: id

    if ids != [] do
      from(a in ExperimentAssignment,
        where: a.id in ^ids and a.room_id == ^room_id and is_nil(a.page_id)
      )
      |> Repo.update_all(set: [page_id: page.id])
    end

    :ok
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

  A tap carrying its Page's `assignment` is recorded under that Assignment's
  Arm.
  """
  @spec record_bookends_tap(Ecto.UUID.t() | String.t(), map()) ::
          {:ok, BookendsTap.t()} | {:error, Ecto.Changeset.t()}
  def record_bookends_tap(room_id, attrs) do
    room_id = resolve_room_id(room_id)

    {assignment, attrs} = Map.pop(attrs, :assignment)
    attrs = attrs |> Map.put(:room_id, room_id) |> put_arm(assignment)

    case %BookendsTap{} |> BookendsTap.changeset(attrs) |> Repo.insert() do
      {:ok, tap} ->
        sync_outcome_taps(room_id, tap)
        {:ok, tap}

      error ->
        error
    end
  end

  defp put_arm(attrs, %Assignment{arm: arm}), do: Map.put(attrs, :arm, arm)
  defp put_arm(attrs, nil), do: attrs

  defp sync_outcome_taps(room_id, tap) do
    of_tap =
      case {tap.page_identifier, tap.page_id} do
        {nil, nil} ->
          nil

        {identifier, nil} ->
          dynamic([o], o.page_identifier == ^identifier)

        {nil, page_id} ->
          dynamic([o], o.page_id == ^page_id)

        {identifier, page_id} ->
          dynamic([o], o.page_identifier == ^identifier or o.page_id == ^page_id)
      end

    # The Page's latest outcome in each Experiment it played under, because a
    # tap is about the Bookends rather than about an Arm and every Experiment's
    # readout may read it. A tap with no outcome of its own is recorded alone
    # rather than attached to whichever Page happens to be latest.
    outcomes =
      (of_tap &&
         from(o in ExperimentOutcome,
           where: o.room_id == ^room_id,
           where: ^of_tap,
           order_by: [asc: o.inserted_at, asc: o.id]
         )
         |> Repo.all()
         |> Enum.group_by(& &1.experiment_id)
         |> Enum.map(fn {_experiment_id, rows} -> List.last(rows) end)) || []

    for outcome <- outcomes do
      updated_taps = Map.put(outcome.taps || %{}, to_string(tap.seat_id), to_string(tap.label))
      outcome |> Ecto.Changeset.change(taps: updated_taps) |> Repo.update()
    end
  end

  # A Room's assignments, oldest first, of one Experiment or of every one.
  defp assignments(room_id, experiment_id \\ nil) do
    from(a in ExperimentAssignment,
      where: a.room_id == ^room_id,
      order_by: [asc: a.assigned_at, asc: a.id]
    )
    |> of_experiment(experiment_id)
    |> Repo.all()
  end

  # A Room's outcomes, oldest first, of one Experiment or of every one.
  defp outcomes(room_id, experiment_id \\ nil) do
    from(o in ExperimentOutcome,
      where: o.room_id == ^room_id,
      order_by: [asc: o.inserted_at, asc: o.id]
    )
    |> of_experiment(experiment_id)
    |> Repo.all()
  end

  # The ids of the Experiments unblinded in a Room.
  defp unblinded_experiment_ids(room_id) do
    from(u in ExperimentUnblinding,
      where: u.room_id == ^room_id,
      distinct: true,
      select: u.experiment_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  defp unblinded?(room_id, experiment_id) do
    from(u in ExperimentUnblinding, where: u.room_id == ^room_id)
    |> of_experiment(experiment_id)
    |> Repo.exists?()
  end

  @typedoc "A Room's experiment rows, loaded once by `page_arms/1` for `page_arm/2`."
  @opaque page_arms :: %{
            assignments: [ExperimentAssignment.t()],
            outcomes: [ExperimentOutcome.t()],
            unblinded: MapSet.t(String.t())
          }

  @doc """
  Loads a Room's assignments, outcomes and unblinded experiments once, for
  `page_arm/2` to read each of its Pages from.
  """
  @spec page_arms(Ecto.UUID.t() | String.t()) :: page_arms()
  def page_arms(room_id_or_slug) do
    room_id = resolve_room_id(room_id_or_slug)

    %{
      assignments: assignments(room_id),
      outcomes: outcomes(room_id),
      unblinded: unblinded_experiment_ids(room_id)
    }
  end

  @doc """
  One Page view's experiment fields, read from its Room's `page_arms/1`.

  A Page's assignment and outcome are matched by its id or by its document's
  own id. A Page plays under every live Experiment at once, so the book files
  it under the one that wrote its Bookends and falls back to whatever row it
  has. Its experiment is that of its assignment, else of its outcome, else Bait
  against plain. Its arm, trap convergence and deep convergence stay nil until
  that experiment is unblinded in the Room.
  """
  @spec page_arm(page_arms(), Page.t()) :: %{
          experiment_id: String.t(),
          experiment_unblinded: boolean(),
          arm: String.t() | nil,
          trap_converged: boolean() | nil,
          deep_converged: boolean() | nil
        }
  def page_arm(page_arms, %Page{} = page) do
    page_ident = to_string(page.document.identifier || page.id)

    of_page? = fn row ->
      row.page_id == page.id or
        (row.room_id == page.room_id and to_string(row.page_identifier) == page_ident)
    end

    outcome = filed_under(page_arms.outcomes, of_page?)
    # Every assignment and outcome names its Experiment and Arm.
    row = filed_under(page_arms.assignments, of_page?) || outcome
    experiment_id = if row, do: row.experiment_id, else: @bait_against_plain_experiment.id
    unblinded? = MapSet.member?(page_arms.unblinded, experiment_id)
    revealed_outcome = if unblinded?, do: outcome

    %{
      experiment_id: experiment_id,
      experiment_unblinded: unblinded?,
      arm: if(unblinded? && row, do: row.arm),
      trap_converged: revealed_outcome && revealed_outcome.trap_converged,
      deep_converged: revealed_outcome && revealed_outcome.deep_converged
    }
  end

  # The one row of a Page the book reads it by: the Author model's, which wrote
  # its Bookends, or whatever row the Page has when it has no such row.
  defp filed_under(rows, of_page?) do
    matching = Enum.filter(rows, of_page?)

    Enum.find(matching, &(&1.experiment_id == @author_model_id)) || List.first(matching)
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
  Blinded progress toward an Experiment's declared sample in one Room. A nil
  Experiment means the Room's active Experiment.

  Counts recorded completed-Page outcomes across both Arms combined. Assignments
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
  Deliberately unblinds an Experiment in one Room, recording when and by whom
  (`attrs`: `unblinded_at`, and optionally `seat_id` and `notes`). A nil
  Experiment means the Room's active Experiment.

  Refused until the Room has recorded the Experiment's declared sample of
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

  # The Experiment in view for a Room: that of its latest outcome, else of its
  # latest assignment, else the Author-model Experiment.
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
  Every Experiment of every Room that has an assignment, newest Room first:
  the Room, the Experiment's definition, whether it is unblinded there, its
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

  # The ids of the Experiments recorded in a Room, from assignments then outcomes.
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
  The qualitative readout of an Experiment in one Room, worked out by
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
           @author_model_id <- experiment_id,
           [_ | _] = bait_outcomes <- outcomes(room_id, @bait_against_plain_experiment.id) do
        {@bait_against_plain_experiment.id, bait_outcomes}
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
  Works out an Experiment's qualitative readout from rows already in memory:
  its outcomes, oldest first, and the Room's fairness taps, overrules and
  Chronicle Page views. This is the readout's test surface; it touches no
  database.

  Returns `%{experiment: definition, <arm>: summary, summary_narrative: text}`.
  Every Arm's summary carries its meld rate, longest and current meld streaks
  and mean attempts to meld. An Author-model or channel Arm adds its Bookends
  taps and closing bands, which is what both declare; a Bait-against-plain Arm
  adds the tally of its current participant Opinions (`Opinion.tally/1`), its
  overrules and its trap and deep convergence.

  Strictly avoids p-values or significance tests: the sample is two people.
  """
  @spec summarize(String.t(), %{
          outcomes: [ExperimentOutcome.t()],
          fairness_taps: [map()],
          overrules: [map()],
          views: [Thereish.Chronicle.PageView.t()]
        }) :: map()
  def summarize(@author_model_id, %{outcomes: outcomes}) do
    flash = summarize_tapped_arm(of_arm(outcomes, "flash"))
    astra = summarize_tapped_arm(of_arm(outcomes, "astra"))

    %{
      experiment: @author_model_experiment,
      flash: flash,
      astra: astra,
      summary_narrative:
        "#{meld_sentence("Flash", flash)} with #{flash.preferences_summary}. " <>
          "#{meld_sentence("Astra", astra)} with #{astra.preferences_summary}."
    }
  end

  # The channel's question is whether a Page with a word spent in it is harder,
  # so its readout is the arc — meld rate and the attempts it took — with the
  # tap on the Bookends beside it. Nothing counts the Nudges themselves
  # (ADR-0023).
  def summarize(@channel_id, %{outcomes: outcomes}) do
    nudge_on = summarize_tapped_arm(of_arm(outcomes, "nudge_on"))
    nudge_off = summarize_tapped_arm(of_arm(outcomes, "nudge_off"))

    %{
      experiment: @channel_experiment,
      nudge_on: nudge_on,
      nudge_off: nudge_off,
      summary_narrative:
        "#{meld_sentence("Pages with a Nudge", nudge_on)} with #{nudge_on.preferences_summary}. " <>
          "#{meld_sentence("Pages without one", nudge_off)} with #{nudge_off.preferences_summary}."
    }
  end

  # Any Experiment but the Author model and the channel reads as Bait against
  # plain, as any other Arm belongs to it.
  def summarize(_bait_against_plain_id, %{outcomes: outcomes} = rows) do
    bait_outcomes = of_arm(outcomes, "bait")
    plain_outcomes = of_arm(outcomes, "plain")
    bait_views = views_of(rows.views, bait_outcomes)
    plain_views = views_of(rows.views, plain_outcomes)

    # Feedback is read from the Arm's Page views; a Room with none of them
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
      experiment: @bait_against_plain_experiment,
      bait: bait,
      plain: plain,
      summary_narrative:
        "#{meld_sentence("Bait-scored pages", bait)} with #{bait.trap_sprung_count} traps sprung and #{bait.fairness_summary}. " <>
          "#{meld_sentence("Plain pages", plain)} with #{plain.fairness_summary} and #{plain.overrules_count} overrules."
    }
  end

  defp meld_sentence(subject, summary) do
    "#{subject} achieved a meld rate of #{summary.meld_rate} " <>
      "(best streak: #{summary.longest_meld_streak}, mean attempts: #{summary.mean_attempts_to_meld})"
  end

  defp of_arm(outcomes, arm), do: Enum.filter(outcomes, &(&1.arm == arm))

  # An Arm read from the arc and the tap on the Bookends. The Author model and
  # the channel declare the same outcomes, so they read out the same way.
  defp summarize_tapped_arm(outcomes) do
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
    %{"fair" => fair, "too_kind" => too_kind, "too_harsh" => too_harsh} =
      Opinion.tally(fairness_taps)

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

  # The meld rate, streaks and mean attempts every Arm's summary shares.
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

  # The Chronicle Page views an Arm's outcomes name, by Page id or the
  # document's own id.
  defp views_of(views, outcomes) do
    identifiers =
      outcomes
      |> Enum.flat_map(&[to_string(&1.page_id), to_string(&1.page_identifier)])
      |> Enum.reject(&(&1 in ["", "nil"]))
      |> MapSet.new()

    Enum.filter(views, fn view ->
      to_string(view.id) in identifiers or to_string(view.document.identifier) in identifiers
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
