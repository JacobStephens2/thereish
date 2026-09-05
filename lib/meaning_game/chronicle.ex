defmodule MeaningGame.Chronicle do
  @moduledoc """
  The record of everything played, written once and never rewritten.

  A Page arrives here when it closes, as the whole thing at once: the authored
  document, every attempt in order, what each Seat wrote on each, and the one
  Verdict the Assayer gave those Bridges read together (ADR-0010). Nothing here updates a row and nothing deletes
  one — the log is the version history (ADR-0003), which is why the couple
  correcting the record later will be another row rather than an edit to this
  one.

  Rows reference Seats and never Accounts. A Seat is permanent and claimable, so
  a history written against one comes with it whenever an Account claims it
  (ADR-0007).

  There is no repository seam under this. Tests run against real Postgres
  through the Ecto sandbox, because a Chronicle that only ever wrote to a fake
  would prove nothing about the thing the couple are going to read.
  """

  import Ecto.Query

  alias MeaningGame.Chronicle.Attempt
  alias MeaningGame.Chronicle.Bridge
  alias MeaningGame.Chronicle.Correction
  alias MeaningGame.Chronicle.ExperimentAssignment
  alias MeaningGame.Chronicle.ExperimentOutcome
  alias MeaningGame.Chronicle.ExperimentUnblinding
  alias MeaningGame.Chronicle.FairnessTap
  alias MeaningGame.Chronicle.Give
  alias MeaningGame.Chronicle.Overrule
  alias MeaningGame.Chronicle.Page
  alias MeaningGame.Chronicle.Recap
  alias MeaningGame.Chronicle.Verdict
  alias MeaningGame.Repo

  @doc """
  Writes one closed Page, with its attempts, its Bridges and its verdicts.

  `entry` is what `MeaningGame.Game` describes when a Page closes, and
  `opened_at` is when the Room dealt it — the Game keeps no clock, so the time a
  Page began is the Room's to remember.

  One transaction, and every insert is a bang: a Page half in the Chronicle is
  worse than a Page that is not in it, so a row that will not go in takes the
  whole write down rather than leaving a torn record behind.
  """
  @spec write(Ecto.UUID.t(), map(), DateTime.t()) :: {:ok, Page.t()}
  def write(room_id, entry, opened_at) do
    Repo.transaction(fn ->
      page = insert_page(room_id, entry, opened_at)

      Enum.each(entry.attempts, &insert_attempt(page, &1))

      page
    end)
  end

  @doc """
  Records one joint player overrule into the Chronicle.
  """
  @spec record_overrule(Ecto.UUID.t(), map()) ::
          {:ok, Overrule.t()} | {:error, Ecto.Changeset.t()}
  def record_overrule(room_id, attrs) do
    attrs = Map.put(attrs, :room_id, room_id)

    %Overrule{}
    |> Overrule.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Records one player correction into the Chronicle as an append-only event.
  """
  @spec record_correction(Ecto.UUID.t(), map()) ::
          {:ok, Correction.t()} | {:error, Ecto.Changeset.t()}
  def record_correction(room_id, attrs) do
    attrs = Map.put(attrs, :room_id, room_id)

    %Correction{}
    |> Correction.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Every overrule in one Room, oldest first.
  """
  @spec overrules(Ecto.UUID.t()) :: [Overrule.t()]
  def overrules(room_id) do
    from(o in Overrule, where: o.room_id == ^room_id, order_by: [asc: o.inserted_at, asc: o.id])
    |> Repo.all()
    |> Repo.preload(:proposer)
  end

  @doc """
  Every correction in one Room, oldest first.
  """
  @spec corrections(Ecto.UUID.t()) :: [Correction.t()]
  def corrections(room_id) do
    from(c in Correction, where: c.room_id == ^room_id, order_by: [asc: c.inserted_at, asc: c.id])
    |> Repo.all()
    |> Repo.preload(:seat)
  end

  @doc """
  Records one recap the Scribe wrote for a closed Page.

  Another row, never an update. The Scribe run twice on one Page leaves two
  recaps and the book reads the later one, so a prompt that got better does not
  erase the paragraph the couple were actually shown (ADR-0003).
  """
  @spec record_recap(Ecto.UUID.t(), map()) :: {:ok, Recap.t()} | {:error, Ecto.Changeset.t()}
  def record_recap(room_id, attrs) do
    meta = Map.get(attrs, :meta, %{})

    attrs =
      attrs
      |> Map.drop([:meta])
      |> Map.merge(Map.take(meta, [:model, :prompt_version, :cost_usd, :latency_ms, :attempts]))
      |> Map.put(:room_id, room_id)

    %Recap{}
    |> Recap.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Every recap in one Room, oldest first.
  """
  @spec recaps(Ecto.UUID.t() | String.t()) :: [Recap.t()]
  def recaps(room_id_or_slug) do
    room_id = resolve_room_id(room_id_or_slug)

    from(r in Recap, where: r.room_id == ^room_id, order_by: [asc: r.inserted_at, asc: r.id])
    |> Repo.all()
  end

  @doc """
  Closed Pages in one Room that have no recap yet, oldest first.
  """
  @spec unrecapped_pages(Ecto.UUID.t() | String.t()) :: [Page.t()]
  def unrecapped_pages(room_id_or_code) do
    room_id = resolve_room_id(room_id_or_code)

    from(p in Page,
      left_join: r in Recap,
      on: r.page_id == p.id,
      where: p.room_id == ^room_id and is_nil(r.id),
      order_by: [asc: p.closed_at, asc: p.id]
    )
    |> Repo.all()
  end

  @doc """
  Records one player fairness tap into the Chronicle as an append-only event.
  """
  @spec record_fairness_tap(Ecto.UUID.t(), map()) ::
          {:ok, FairnessTap.t()} | {:error, Ecto.Changeset.t()}
  def record_fairness_tap(room_id, attrs) do
    attrs = Map.put(attrs, :room_id, room_id)

    %FairnessTap{}
    |> FairnessTap.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Every fairness tap in one Room, oldest first.
  """
  @spec fairness_taps(Ecto.UUID.t() | String.t()) :: [FairnessTap.t()]
  def fairness_taps(room_id_or_slug) do
    room_id = resolve_room_id(room_id_or_slug)

    from(t in FairnessTap,
      where: t.room_id == ^room_id,
      order_by: [asc: t.inserted_at, asc: t.id]
    )
    |> Repo.all()
    |> Repo.preload(:seat)
  end

  @doc """
  Every fairness tap across all Rooms, oldest first.
  """
  @spec all_fairness_taps() :: [FairnessTap.t()]
  def all_fairness_taps do
    from(t in FairnessTap, order_by: [asc: t.inserted_at, asc: t.id])
    |> Repo.all()
    |> Repo.preload(:seat)
  end

  @doc """
  Returns the labelled set in structured map form for calibration runs.
  """
  @spec calibration_dataset(Ecto.UUID.t() | String.t() | nil) :: [map()]
  def calibration_dataset(room_id_or_slug \\ nil) do
    taps =
      if room_id_or_slug do
        fairness_taps(room_id_or_slug)
      else
        all_fairness_taps()
      end

    Enum.map(taps, &format_calibration_entry/1)
  end

  @doc """
  Exports the labelled set in a format a calibration run can consume (:json or :jsonl).
  """
  @spec export_calibration(Ecto.UUID.t() | String.t() | nil, :json | :jsonl) :: String.t()
  def export_calibration(room_id_or_slug \\ nil, format \\ :json) do
    dataset = calibration_dataset(room_id_or_slug)

    case format do
      :json ->
        Jason.encode!(dataset, pretty: true)

      :jsonl ->
        dataset
        |> Enum.map(&Jason.encode!/1)
        |> Enum.join("\n")
    end
  end

  defp format_calibration_entry(t) do
    format_fairness_tap(t)
    |> Map.merge(%{
      room_id: t.room_id,
      page_id: t.page_id
    })
  end

  @doc """
  Records one experiment arm assignment for a Page as an append-only event (ticket 13).
  """
  @spec record_experiment_assignment(Ecto.UUID.t(), map()) ::
          {:ok, ExperimentAssignment.t()} | {:error, Ecto.Changeset.t()}
  def record_experiment_assignment(room_id, attrs) do
    attrs = Map.put(attrs, :room_id, room_id)

    %ExperimentAssignment{}
    |> ExperimentAssignment.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Records one experiment outcome for a Page as an append-only event (ticket 13).
  """
  @spec record_experiment_outcome(Ecto.UUID.t(), map()) ::
          {:ok, ExperimentOutcome.t()} | {:error, Ecto.Changeset.t()}
  def record_experiment_outcome(room_id, attrs) do
    attrs = Map.put(attrs, :room_id, room_id)

    %ExperimentOutcome{}
    |> ExperimentOutcome.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Records an experiment outcome for a closed Page, extracting convergence flags and identifiers.
  """
  @spec record_page_outcome(Ecto.UUID.t(), map(), map(), atom() | String.t(), String.t()) ::
          {:ok, ExperimentOutcome.t()} | {:error, Ecto.Changeset.t()}
  def record_page_outcome(room_id, page, entry, arm, experiment_id \\ "bait_against_plain") do
    trap_converged =
      Enum.any?(entry.attempts, fn att ->
        Enum.any?(att.verdicts, fn v ->
          meta = (is_map(v) && (v[:meta] || Map.get(v, :meta))) || %{}
          meta[:trap_sprung] == true or meta["trap_sprung"] == true
        end)
      end)

    deep_converged =
      Enum.any?(entry.attempts, fn att ->
        Enum.any?(att.verdicts, fn v ->
          meta = (is_map(v) && (v[:meta] || Map.get(v, :meta))) || %{}
          meta[:deep_convergence] == true or meta["deep_convergence"] == true
        end)
      end)

    page_identifier =
      cond do
        is_map(entry.page) -> entry.page[:id] || entry.page["id"] || page.id
        true -> page.id
      end

    record_experiment_outcome(room_id, %{
      page_id: page.id,
      page_identifier: to_string(page_identifier),
      experiment_id: experiment_id,
      arm: to_string(arm),
      melded: entry.melded?,
      closeness: entry.closeness,
      attempts_count: length(entry.attempts),
      closed_because: to_string(entry.closed_because),
      trap_converged: trap_converged,
      deep_converged: deep_converged
    })
  end

  @doc """
  Records an unblinding action for an experiment as an append-only event (ticket 13).
  """
  @spec record_experiment_unblinding(Ecto.UUID.t(), map()) ::
          {:ok, ExperimentUnblinding.t()} | {:error, Ecto.Changeset.t()}
  def record_experiment_unblinding(room_id, attrs) do
    attrs = Map.put(attrs, :room_id, room_id)

    %ExperimentUnblinding{}
    |> ExperimentUnblinding.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns all experiment assignments for a Room, oldest first.
  """
  @spec experiment_assignments(Ecto.UUID.t() | String.t(), String.t()) ::
          [ExperimentAssignment.t()]
  def experiment_assignments(room_id_or_slug, experiment_id \\ "bait_against_plain") do
    room_id = resolve_room_id(room_id_or_slug)

    from(a in ExperimentAssignment,
      where: a.room_id == ^room_id and a.experiment_id == ^experiment_id,
      order_by: [asc: a.assigned_at, asc: a.id]
    )
    |> Repo.all()
  end

  @doc """
  Returns all experiment outcomes for a Room, oldest first.
  """
  @spec experiment_outcomes(Ecto.UUID.t() | String.t(), String.t()) :: [ExperimentOutcome.t()]
  def experiment_outcomes(room_id_or_slug, experiment_id \\ "bait_against_plain") do
    room_id = resolve_room_id(room_id_or_slug)

    from(o in ExperimentOutcome,
      where: o.room_id == ^room_id and o.experiment_id == ^experiment_id,
      order_by: [asc: o.inserted_at, asc: o.id]
    )
    |> Repo.all()
  end

  @doc """
  Returns all unblindings for a Room, oldest first.
  """
  @spec experiment_unblindings(Ecto.UUID.t() | String.t(), String.t()) ::
          [ExperimentUnblinding.t()]
  def experiment_unblindings(room_id_or_slug, experiment_id \\ "bait_against_plain") do
    room_id = resolve_room_id(room_id_or_slug)

    from(u in ExperimentUnblinding,
      where: u.room_id == ^room_id and u.experiment_id == ^experiment_id,
      order_by: [asc: u.unblinded_at, asc: u.id]
    )
    |> Repo.all()
  end

  @doc """
  Whether the given experiment has been deliberately unblinded in this Room.
  """
  @spec experiment_unblinded?(Ecto.UUID.t() | String.t(), String.t()) :: boolean()
  def experiment_unblinded?(room_id_or_slug, experiment_id \\ "bait_against_plain") do
    room_id = resolve_room_id(room_id_or_slug)

    Repo.exists?(
      from(u in ExperimentUnblinding,
        where: u.room_id == ^room_id and u.experiment_id == ^experiment_id
      )
    )
  end

  @doc """
  Returns past assigned arms in the given chapter stratum.
  """
  @spec chapter_assignments(Ecto.UUID.t() | String.t(), String.t(), String.t()) :: [atom()]
  def chapter_assignments(room_id_or_slug, chapter, experiment_id \\ "bait_against_plain") do
    room_id = resolve_room_id(room_id_or_slug)

    from(a in ExperimentAssignment,
      where:
        a.room_id == ^room_id and a.chapter == ^chapter and a.experiment_id == ^experiment_id,
      order_by: [asc: a.assigned_at, asc: a.id],
      select: a.arm
    )
    |> Repo.all()
    |> Enum.map(&String.to_atom/1)
  end

  @doc """
  Computes the qualitative readout for an experiment in a Room.
  """
  @spec experiment_readout(Ecto.UUID.t() | String.t(), String.t()) :: map()
  def experiment_readout(room_id_or_slug, experiment_id \\ "bait_against_plain") do
    room_id = resolve_room_id(room_id_or_slug)
    outcomes = experiment_outcomes(room_id, experiment_id)
    views = page_views(room_id)
    taps = fairness_taps(room_id)
    overrules = overrules(room_id)

    data = summarize_experiment_data(outcomes, taps, overrules, views)
    MeaningGame.Experiments.qualitative_readout(data)
  end

  defp summarize_experiment_data(outcomes, taps, overrules, views) do
    bait_outcomes = Enum.filter(outcomes, &(&1.arm == "bait"))
    plain_outcomes = Enum.filter(outcomes, &(&1.arm == "plain"))

    bait_page_identifiers =
      Enum.flat_map(bait_outcomes, &[to_string(&1.page_id), to_string(&1.page_identifier)])
      |> Enum.reject(&(&1 in ["", "nil"]))
      |> MapSet.new()

    plain_page_identifiers =
      Enum.flat_map(plain_outcomes, &[to_string(&1.page_id), to_string(&1.page_identifier)])
      |> Enum.reject(&(&1 in ["", "nil"]))
      |> MapSet.new()

    bait_views =
      Enum.filter(views, fn v ->
        to_string(v.id) in bait_page_identifiers or
          to_string(v.document["id"]) in bait_page_identifiers
      end)

    plain_views =
      Enum.filter(views, fn v ->
        to_string(v.id) in plain_page_identifiers or
          to_string(v.document["id"]) in plain_page_identifiers
      end)

    {taps_bait, taps_plain} =
      if bait_views != [] or plain_views != [] do
        {
          Enum.flat_map(bait_views, & &1.fairness_taps),
          Enum.flat_map(plain_views, & &1.fairness_taps)
        }
      else
        page_ids_bait = Enum.map(bait_outcomes, & &1.page_id) |> Enum.reject(&is_nil/1)
        page_ids_plain = Enum.map(plain_outcomes, & &1.page_id) |> Enum.reject(&is_nil/1)

        {
          Enum.filter(taps, &(&1.page_id in page_ids_bait)),
          Enum.filter(taps, &(&1.page_id in page_ids_plain))
        }
      end

    {overrules_bait_count, overrules_plain_count} =
      if bait_views != [] or plain_views != [] do
        {
          Enum.flat_map(bait_views, & &1.overrules) |> length(),
          Enum.flat_map(plain_views, & &1.overrules) |> length()
        }
      else
        page_ids_bait = Enum.map(bait_outcomes, & &1.page_id) |> Enum.reject(&is_nil/1)
        page_ids_plain = Enum.map(plain_outcomes, & &1.page_id) |> Enum.reject(&is_nil/1)

        {
          Enum.count(overrules, &(&1.page_id in page_ids_bait)),
          Enum.count(overrules, &(&1.page_id in page_ids_plain))
        }
      end

    %{
      bait: summarize_arm_raw(bait_outcomes, taps_bait, overrules_bait_count),
      plain: summarize_arm_raw(plain_outcomes, taps_plain, overrules_plain_count)
    }
  end

  defp summarize_arm_raw(outcomes, taps, overrules_count) do
    %{
      pages_count: length(outcomes),
      melded_count: Enum.count(outcomes, & &1.melded),
      melded_history: Enum.map(outcomes, & &1.melded),
      attempts_to_meld: outcomes |> Enum.filter(& &1.melded) |> Enum.map(& &1.attempts_count),
      fairness_taps: Enum.frequencies_by(taps, & &1.label),
      overrules_count: overrules_count,
      trap_sprung_count: Enum.count(outcomes, & &1.trap_converged),
      deep_convergence_count: Enum.count(outcomes, & &1.deep_converged)
    }
  end

  @doc """
  Every closed Page in one Room, oldest first, with its attempts, Bridges and
  verdicts loaded.

  The book (and the Markdown export under it) is a view computed from these rows
  rather than a second copy of them.
  """
  @spec pages(Ecto.UUID.t()) :: [Page.t()]
  def pages(room_id) do
    from(p in Page, where: p.room_id == ^room_id, order_by: [asc: p.closed_at, asc: p.id])
    |> Repo.all()
    |> Repo.preload(attempts: [:bridges, :verdicts])
  end

  @doc """
  Computes the book view from the event log for one Room, in reverse
  chronological order (newest Page first).

  No stored copy of a view exists anywhere (design law 5, ADR-0003). The view is
  projected directly from the append-only rows: Pages, attempts, bridges, verdicts,
  overrules, and corrections.
  """
  @spec book(Ecto.UUID.t() | String.t()) :: [map()]
  def book(room_id_or_slug), do: page_views(room_id_or_slug, :desc)

  @doc """
  Computes views of all Pages in one Room directly from the event log, in the
  given order (:asc or :desc).
  """
  @spec page_views(Ecto.UUID.t() | String.t(), :asc | :desc) :: [map()]
  def page_views(room_id_or_slug, order \\ :desc) do
    room_id = resolve_room_id(room_id_or_slug)

    pages =
      from(p in Page,
        where: p.room_id == ^room_id,
        order_by: [{^order, p.closed_at}, {^order, p.id}]
      )
      |> Repo.all()
      |> Repo.preload(
        gives: :seat,
        attempts: [:verdicts, bridges: :seat],
        overrules: :proposer,
        corrections: :seat
      )

    all_overrules = overrules(room_id)
    all_corrections = corrections(room_id)
    all_recaps = recaps(room_id)
    all_taps = fairness_taps(room_id)
    all_assignments = experiment_assignments(room_id)
    all_outcomes = experiment_outcomes(room_id)
    unblinded? = experiment_unblinded?(room_id)

    Enum.map(
      pages,
      &compute_page_view(
        &1,
        all_overrules,
        all_corrections,
        all_taps,
        all_assignments,
        all_outcomes,
        all_recaps,
        unblinded?
      )
    )
  end

  @doc """
  Renders the Chronicle for a Room as a Markdown document on demand.
  """
  @spec to_markdown(Ecto.UUID.t() | String.t()) :: String.t()
  def to_markdown(room_id_or_slug), do: MeaningGame.Chronicle.Markdown.render(room_id_or_slug)

  @doc """
  Parses an exported Chronicle Markdown document back into structured data.
  """
  @spec from_markdown(String.t()) :: {:ok, [map()]} | {:error, term()}
  def from_markdown(markdown), do: MeaningGame.Chronicle.Markdown.parse(markdown)

  @doc """
  Answers spend for all Rooms across Author, Assayer, and Scribe calls.
  """
  @spec spend() :: map()
  def spend, do: spend(:all)

  @doc """
  Answers spend for one Room or for all Rooms across Author, Assayer, and Scribe calls.

  Totals dollars, by role, and by model with call counts and unpriced call counts,
  computed dynamically from rows (never stored as a total).
  """
  @spec spend(Ecto.UUID.t() | String.t() | :all) :: map()
  def spend(:all) do
    all_rooms = Repo.all(from(r in MeaningGame.Rooms.Room, order_by: [asc: r.slug]))

    all_pages =
      Repo.all(
        from(p in Page,
          select: %{
            room_id: p.room_id,
            author_meta: p.author_meta
          }
        )
      )

    all_verdicts =
      Repo.all(
        from(v in Verdict,
          join: a in Attempt,
          on: a.id == v.attempt_id,
          join: p in Page,
          on: p.id == a.page_id,
          select: %{
            room_id: p.room_id,
            model: v.model,
            cost_usd: v.cost_usd
          }
        )
      )

    all_recaps =
      Repo.all(
        from(r in Recap,
          select: %{
            room_id: r.room_id,
            model: r.model,
            cost_usd: r.cost_usd
          }
        )
      )

    pages_by_room = Enum.group_by(all_pages, & &1.room_id)
    verdicts_by_room = Enum.group_by(all_verdicts, & &1.room_id)
    recaps_by_room = Enum.group_by(all_recaps, & &1.room_id)

    rooms_spend =
      Enum.map(all_rooms, fn room ->
        p_list = Map.get(pages_by_room, room.id, [])
        v_list = Map.get(verdicts_by_room, room.id, [])
        r_list = Map.get(recaps_by_room, room.id, [])

        compute_room_spend(room, p_list, v_list, r_list)
      end)

    total_acc =
      Enum.reduce(rooms_spend, empty_spend_acc(), fn room_spend, acc ->
        merge_spend_acc(acc, room_spend)
      end)

    Map.put(total_acc, :rooms, rooms_spend)
  end

  def spend(room_id_or_slug) do
    room_id = resolve_room_id(room_id_or_slug)
    room = Repo.get!(MeaningGame.Rooms.Room, room_id)

    pages =
      Repo.all(
        from(p in Page,
          where: p.room_id == ^room.id,
          select: %{author_meta: p.author_meta}
        )
      )

    verdicts =
      Repo.all(
        from(v in Verdict,
          join: a in Attempt,
          on: a.id == v.attempt_id,
          join: p in Page,
          on: p.id == a.page_id,
          where: p.room_id == ^room.id,
          select: %{model: v.model, cost_usd: v.cost_usd}
        )
      )

    recaps =
      Repo.all(
        from(r in Recap,
          where: r.room_id == ^room.id,
          select: %{model: r.model, cost_usd: r.cost_usd}
        )
      )

    compute_room_spend(room, pages, verdicts, recaps)
  end

  @doc """
  Formats the spend line for display in the book view and Markdown export.
  """
  @spec spend_line(map()) :: String.t()
  def spend_line(spend) do
    calls_word = if spend.calls_count == 1, do: "call", else: "calls"

    unpriced_str =
      if spend.unpriced_count > 0, do: " (#{spend.unpriced_count} unpriced)", else: ""

    role_str = fn role_name, role_key ->
      role_data =
        get_in(spend, [:by_role, role_key]) ||
          %{total_usd: Decimal.new(0), calls_count: 0, unpriced_count: 0}

      cond do
        role_data.calls_count == 0 ->
          "#{role_name} $0.0000"

        role_data.unpriced_count == role_data.calls_count ->
          "#{role_name} unpriced"

        role_data.unpriced_count > 0 ->
          "#{role_name} #{format_usd(role_data.total_usd)} (#{role_data.unpriced_count} unpriced)"

        true ->
          "#{role_name} #{format_usd(role_data.total_usd)}"
      end
    end

    roles_summary =
      Enum.map([{"Author", :author}, {"Assayer", :assayer}, {"Scribe", :scribe}], fn {name, key} ->
        role_str.(name, key)
      end)
      |> Enum.join(", ")

    "Spend: #{format_usd(spend.total_usd)} across #{spend.calls_count} #{calls_word}#{unpriced_str} (#{roles_summary})"
  end

  @doc """
  Formats a dollar decimal or float as a 4-decimal currency string (e.g. "$0.0042").
  """
  @spec format_usd(Decimal.t() | number() | binary() | nil) :: String.t()
  def format_usd(nil), do: "$0.0000"

  def format_usd(%Decimal{} = dec) do
    rounded = Decimal.round(dec, 4)
    "$" <> Decimal.to_string(rounded, :normal)
  end

  def format_usd(val) when is_number(val) or is_binary(val) do
    case to_decimal(val) do
      nil -> "$0.0000"
      dec -> format_usd(dec)
    end
  end

  defp compute_room_spend(room, pages, verdicts, recaps) do
    acc0 = %{
      room_id: room.id,
      slug: room.slug,
      total_usd: Decimal.new(0),
      calls_count: 0,
      unpriced_count: 0,
      by_role: %{
        author: %{
          total_usd: Decimal.new(0),
          calls_count: 0,
          unpriced_count: 0,
          by_model: %{}
        },
        assayer: %{
          total_usd: Decimal.new(0),
          calls_count: 0,
          unpriced_count: 0,
          by_model: %{}
        },
        scribe: %{
          total_usd: Decimal.new(0),
          calls_count: 0,
          unpriced_count: 0,
          by_model: %{}
        }
      },
      by_model: %{}
    }

    acc1 =
      Enum.reduce(pages, acc0, fn page, acc ->
        meta = page.author_meta

        if is_map(meta) and map_size(meta) > 0 do
          model = meta["model"] || meta[:model] || "unknown"
          cost = to_decimal(meta["cost_usd"] || meta[:cost_usd])
          record_call(acc, :author, model, cost)
        else
          acc
        end
      end)

    acc2 =
      Enum.reduce(verdicts, acc1, fn verdict, acc ->
        model = verdict.model || "unknown"
        cost = to_decimal(verdict.cost_usd)
        record_call(acc, :assayer, model, cost)
      end)

    Enum.reduce(recaps, acc2, fn recap, acc ->
      model = recap.model || "unknown"
      cost = to_decimal(recap.cost_usd)
      record_call(acc, :scribe, model, cost)
    end)
  end

  defp empty_spend_acc do
    %{
      total_usd: Decimal.new(0),
      calls_count: 0,
      unpriced_count: 0,
      by_role: %{
        author: %{
          total_usd: Decimal.new(0),
          calls_count: 0,
          unpriced_count: 0,
          by_model: %{}
        },
        assayer: %{
          total_usd: Decimal.new(0),
          calls_count: 0,
          unpriced_count: 0,
          by_model: %{}
        },
        scribe: %{
          total_usd: Decimal.new(0),
          calls_count: 0,
          unpriced_count: 0,
          by_model: %{}
        }
      },
      by_model: %{}
    }
  end

  defp merge_spend_acc(acc, item) do
    new_total = Decimal.add(acc.total_usd, item.total_usd)
    new_calls = acc.calls_count + item.calls_count
    new_unpriced = acc.unpriced_count + item.unpriced_count

    merged_roles =
      Enum.reduce([:author, :assayer, :scribe], acc.by_role, fn role, roles_acc ->
        r1 =
          Map.get(roles_acc, role, %{
            total_usd: Decimal.new(0),
            calls_count: 0,
            unpriced_count: 0,
            by_model: %{}
          })

        r2 =
          Map.get(item.by_role, role, %{
            total_usd: Decimal.new(0),
            calls_count: 0,
            unpriced_count: 0,
            by_model: %{}
          })

        merged_role_models =
          Enum.reduce(r2.by_model, r1.by_model, fn {m, m_stats2}, m_acc ->
            m_stats1 =
              Map.get(m_acc, m, %{
                total_usd: Decimal.new(0),
                calls_count: 0,
                unpriced_count: 0
              })

            Map.put(m_acc, m, %{
              total_usd: Decimal.add(m_stats1.total_usd, m_stats2.total_usd),
              calls_count: m_stats1.calls_count + m_stats2.calls_count,
              unpriced_count: m_stats1.unpriced_count + m_stats2.unpriced_count
            })
          end)

        Map.put(roles_acc, role, %{
          total_usd: Decimal.add(r1.total_usd, r2.total_usd),
          calls_count: r1.calls_count + r2.calls_count,
          unpriced_count: r1.unpriced_count + r2.unpriced_count,
          by_model: merged_role_models
        })
      end)

    merged_models =
      Enum.reduce(item.by_model, acc.by_model, fn {model, m2}, models_acc ->
        m1 =
          Map.get(models_acc, model, %{
            total_usd: Decimal.new(0),
            calls_count: 0,
            unpriced_count: 0
          })

        Map.put(models_acc, model, %{
          total_usd: Decimal.add(m1.total_usd, m2.total_usd),
          calls_count: m1.calls_count + m2.calls_count,
          unpriced_count: m1.unpriced_count + m2.unpriced_count
        })
      end)

    %{
      acc
      | total_usd: new_total,
        calls_count: new_calls,
        unpriced_count: new_unpriced,
        by_role: merged_roles,
        by_model: merged_models
    }
  end

  defp record_call(acc, role, model, cost) do
    {cost_dec, unpriced_delta} =
      case cost do
        nil -> {Decimal.new(0), 1}
        %Decimal{} = d -> {d, 0}
      end

    new_total = Decimal.add(acc.total_usd, cost_dec)
    new_calls = acc.calls_count + 1
    new_unpriced = acc.unpriced_count + unpriced_delta

    model_key = to_string(model || "unknown")

    role_acc =
      Map.get(acc.by_role, role, %{
        total_usd: Decimal.new(0),
        calls_count: 0,
        unpriced_count: 0,
        by_model: %{}
      })

    role_model_stats =
      Map.get(role_acc.by_model, model_key, %{
        total_usd: Decimal.new(0),
        calls_count: 0,
        unpriced_count: 0
      })
      |> update_stats(cost_dec, unpriced_delta)

    new_role_by_model = Map.put(role_acc.by_model, model_key, role_model_stats)

    role_stats =
      role_acc
      |> update_stats(cost_dec, unpriced_delta)
      |> Map.put(:by_model, new_role_by_model)

    model_stats =
      Map.get(acc.by_model, model_key, %{
        total_usd: Decimal.new(0),
        calls_count: 0,
        unpriced_count: 0
      })
      |> update_stats(cost_dec, unpriced_delta)

    %{
      acc
      | total_usd: new_total,
        calls_count: new_calls,
        unpriced_count: new_unpriced,
        by_role: Map.put(acc.by_role, role, role_stats),
        by_model: Map.put(acc.by_model, model_key, model_stats)
    }
  end

  defp update_stats(stats, cost_dec, unpriced_delta) do
    %{
      total_usd: Decimal.add(stats.total_usd, cost_dec),
      calls_count: stats.calls_count + 1,
      unpriced_count: stats.unpriced_count + unpriced_delta
    }
  end

  defp to_decimal(nil), do: nil
  defp to_decimal(%Decimal{} = d), do: d
  defp to_decimal(f) when is_float(f), do: Decimal.from_float(f)
  defp to_decimal(i) when is_integer(i), do: Decimal.new(i)

  defp to_decimal(s) when is_binary(s) do
    case Decimal.parse(s) do
      {d, ""} -> d
      _ -> nil
    end
  end

  defp to_decimal(_), do: nil

  @doc """
  Returns the last `count` quips recorded in a Room's Chronicle, in chronological order.

  Looks first in the database for a Room with the given Code or UUID. If not found in
  the database, looks for a Chronicle Markdown file at `priv/chronicles/<code>.md`.
  """
  @spec recent_quips(Ecto.UUID.t() | String.t(), pos_integer()) :: [String.t()]
  def recent_quips(room_code_or_id, count \\ 5) do
    quips =
      case safe_resolve_room_id(room_code_or_id) do
        {:ok, room_id} ->
          views = page_views(room_id, :asc)

          for page <- views,
              attempt <- page.attempts,
              quip <- quips_from_attempt(attempt) do
            quip
          end

        :error ->
          chronicle_path =
            if is_binary(room_code_or_id) do
              code = String.downcase(room_code_or_id)

              candidates = [
                try do
                  Application.app_dir(
                    :meaning_game,
                    Path.join(["priv", "chronicles", "#{code}.md"])
                  )
                rescue
                  _ -> nil
                end,
                Path.join(["priv", "chronicles", "#{code}.md"])
              ]

              Enum.find(candidates, &(&1 && File.exists?(&1)))
            end

          if chronicle_path do
            {:ok, pages} = File.read!(chronicle_path) |> from_markdown()

            for page <- pages,
                attempt <- page.attempts,
                quip <- quips_from_attempt(attempt) do
              quip
            end
          else
            []
          end
      end

    Enum.take(quips, -count)
  end

  defp quips_from_attempt(attempt) do
    cond do
      is_binary(attempt[:quip]) and attempt[:quip] != "" ->
        [attempt[:quip]]

      is_list(attempt[:verdicts]) ->
        for v <- attempt.verdicts, is_binary(v[:quip]) and v[:quip] != "", do: v[:quip]

      true ->
        []
    end
  end

  defp safe_resolve_room_id(room_code_or_id) do
    {:ok, resolve_room_id(room_code_or_id)}
  rescue
    _ ->
      if is_binary(room_code_or_id) do
        case Repo.get_by(MeaningGame.Rooms.Room, slug: String.downcase(room_code_or_id)) do
          nil -> :error
          room -> {:ok, room.id}
        end
      else
        :error
      end
  end

  @doc """
  Composes a concise digest of the Chronicle for feeding to models.

  Returns a default message if no Pages have been played yet.
  """
  @spec digest(Ecto.UUID.t() | String.t()) :: String.t()
  def digest(room_id_or_slug), do: compose_digest(page_views(room_id_or_slug, :asc), false, nil)

  @doc """
  The same digest, with every recap the Scribe has already written folded in.

  Only the Scribe reads this one. A callback is a line that remembers an earlier
  evening, so the Scribe has to be able to see the evenings it has already
  written about — including its own prose, so that it does not plant the same
  callback twice.

  The Author reads `digest/1` and not this. What a callback is allowed to touch
  is the Chronicle and nothing else: tonight's candy cane may turn up in next
  month's recap, and it may not quietly become next month's Bookends.
  """
  @spec scribe_digest(Ecto.UUID.t() | String.t() | [map()], Ecto.UUID.t() | nil) :: String.t()
  def scribe_digest(views_or_room, except_page_id \\ nil)

  # Composed from Page views the caller already has, for the Scribe — which
  # reads one Page out of the same list it is about to leave out of the digest,
  # and should not have to compute the book twice to do it. The views must be
  # oldest first, because the digest numbers its Pages.
  def scribe_digest(views, except_page_id) when is_list(views),
    do: compose_digest(views, true, except_page_id)

  def scribe_digest(room_id_or_slug, except_page_id),
    do: compose_digest(page_views(room_id_or_slug, :asc), true, except_page_id)

  defp compose_digest(views, with_recaps?, except_page_id) do
    views = Enum.reject(views, &(except_page_id && &1.id == except_page_id))

    if views == [] do
      "Nothing yet; this is the first Page."
    else
      views
      |> Enum.with_index(1)
      |> Enum.map(&digest_page(&1, with_recaps?))
      |> Enum.join("\n\n")
    end
  end

  defp digest_page({page, index}, with_recaps?) do
    bookends_str = Enum.join(page.bookends, " · ")

    last_attempt = List.last(page.attempts)
    last_verdict = last_attempt && List.first(last_attempt.verdicts)

    outcome_str =
      if page.melded do
        band_str = (last_verdict && last_verdict.band && ", #{last_verdict.band}") || ""
        "Melded on attempt #{last_attempt.number} (closeness: #{page.closeness}#{band_str})"
      else
        "Unmelded after #{length(page.attempts)} attempts"
      end

    give_str =
      cond do
        page[:gives] && page[:gives] != [] ->
          " [" <>
            Enum.map_join(
              page.gives,
              ", ",
              &"Give (#{Map.get(&1, :seat_name, "Player")}): #{Map.get(&1, :text, "")}"
            ) <> "]"

        page[:give] ->
          " [Give: #{page.give}]"

        true ->
          ""
      end

    lines = [
      "Page #{index} (#{bookends_str})#{give_str} — #{outcome_str}"
    ]

    attempt_lines =
      Enum.flat_map(page.attempts, fn attempt ->
        bridges_str =
          attempt.bridges
          |> Enum.map(fn b -> ~s(#{b.seat_name} bridged "#{b.bridge}") end)
          |> Enum.join(", ")

        case attempt.verdicts do
          [] ->
            ["  Attempt #{attempt.number}: #{bridges_str}. Verdict: Ungraded"]

          [single] ->
            band_str = (single.band && " (#{single.band})") || ""
            reason_str = (single.reasoning && " — #{single.reasoning}") || ""

            [
              "  Attempt #{attempt.number}: #{bridges_str}. Verdict: #{single.closeness}#{band_str}#{reason_str}"
            ]

          # An attempt written before ADR-0010, when the Assayer answered one
          # pair at a time. The book is append-only, so those rows are still
          # read out the way they were written.
          multiple ->
            pair_lines =
              Enum.map(multiple, fn v ->
                band_str = (v.band && " (#{v.band})") || ""
                reason_str = (v.reasoning && " — #{v.reasoning}") || ""
                bridges_label = Enum.join(v.bridges, " / ")
                "    Pair [#{bridges_label}]: #{v.closeness}#{band_str}#{reason_str}"
              end)

            ["  Attempt #{attempt.number}: #{bridges_str}." | pair_lines]
        end
      end)

    overrule_lines =
      Enum.map(page.overrules, fn o ->
        "  Overruled: #{o.proposer_name} proposed overrule to #{o.couple_closeness} (\"#{o.couple_reasoning}\")"
      end)

    correction_lines =
      Enum.map(page.corrections, fn c ->
        orig = (c.original_value && " from \"#{c.original_value}\"") || ""
        note = (c.note && " (\"#{c.note}\")") || ""

        "  Correction by #{c.author_name}: corrected #{c.target}#{orig} to \"#{c.corrected_value}\"#{note}"
      end)

    recap_lines =
      case {with_recaps?, page[:recap]} do
        {true, %{recap: recap} = written} when is_binary(recap) ->
          callback = written[:callback]

          ["  Recap: #{recap}"] ++
            if(is_binary(callback), do: ["  Callback: #{callback}"], else: [])

        _no_recap ->
          []
      end

    Enum.join(
      lines ++ attempt_lines ++ overrule_lines ++ correction_lines ++ recap_lines,
      "\n"
    )
  end

  def compute_page_view(
        %Page{} = page,
        all_overrules,
        all_corrections,
        all_taps \\ [],
        all_assignments \\ [],
        all_outcomes \\ [],
        all_recaps \\ [],
        unblinded? \\ false
      ) do
    page_overrules =
      Enum.filter(all_overrules, fn o ->
        o.page_id == page.id or
          (o.room_id == page.room_id and
             Enum.any?(
               page.attempts,
               &(&1.number == o.attempt_number and &1.bookends == o.bookends)
             ))
      end)

    page_corrections =
      Enum.filter(all_corrections, fn c ->
        c.page_id == page.id
      end)

    page_recap = latest_recap(all_recaps, page, page_corrections)

    page_taps =
      Enum.filter(all_taps, fn t ->
        t.page_id == page.id or
          (t.room_id == page.room_id and
             Enum.any?(
               page.attempts,
               &(&1.number == t.attempt_number and &1.bookends == t.bookends)
             ))
      end)

    attempts =
      Enum.map(page.attempts, fn attempt ->
        attempt_overrules =
          Enum.filter(page_overrules, fn o ->
            o.attempt_number == attempt.number and
              (o.bookends == attempt.bookends or o.page_id == page.id)
          end)

        attempt_corrections =
          Enum.filter(page_corrections, fn c ->
            c.attempt_number == attempt.number
          end)

        attempt_taps =
          Enum.filter(page_taps, fn t ->
            t.attempt_number == attempt.number and
              (t.bookends == attempt.bookends or t.page_id == page.id)
          end)

        bridges =
          Enum.map(attempt.bridges, fn b ->
            matching_corrs =
              Enum.filter(page_corrections, fn c ->
                c.target == "bridge" and
                  (c.attempt_number == attempt.number or is_nil(c.attempt_number)) and
                  ((c.original_value && c.original_value == b.bridge) or
                     ((c.attempt_number == attempt.number and c.seat_id) && c.seat_id == b.seat_id))
              end)

            matching_corr = List.last(matching_corrs)

            if matching_corr do
              %{
                id: b.id,
                seat_id: b.seat_id,
                seat_name: (b.seat && b.seat.name) || "Player",
                bridge: matching_corr.corrected_value,
                original_bridge: b.bridge,
                corrected?: true,
                position: b.position
              }
            else
              %{
                id: b.id,
                seat_id: b.seat_id,
                seat_name: (b.seat && b.seat.name) || "Player",
                bridge: b.bridge,
                original_bridge: nil,
                corrected?: false,
                position: b.position
              }
            end
          end)

        verdicts =
          Enum.map(attempt.verdicts, fn v ->
            %{
              id: v.id,
              seat_ids: v.seat_ids,
              bridges: v.bridges,
              graded: v.graded,
              closeness: v.closeness,
              band: v.band,
              reasoning: v.reasoning,
              quip: v.quip,
              overruled: v.overruled || attempt_overrules != [],
              model: v.model,
              prompt_version: v.prompt_version,
              latency_ms: v.latency_ms,
              cost_usd: v.cost_usd,
              forward: v.forward,
              reverse: v.reverse,
              reasoning_reverse: v.reasoning_reverse,
              furthest: v.furthest,
              position: v.position
            }
          end)

        %{
          id: attempt.id,
          number: attempt.number,
          bookends: attempt.bookends,
          closeness: attempt.closeness,
          melded: attempt.melded,
          bridges: bridges,
          verdicts: verdicts,
          overrules: Enum.map(attempt_overrules, &format_overrule/1),
          corrections: Enum.map(attempt_corrections, &format_correction/1),
          fairness_taps: Enum.map(attempt_taps, &format_fairness_tap/1)
        }
      end)

    formatted_gives =
      case page.gives do
        %Ecto.Association.NotLoaded{} ->
          []

        nil ->
          []

        list when is_list(list) ->
          Enum.map(list, fn g ->
            %{
              id: g.id,
              seat_id: g.seat_id,
              seat_name: (g.seat && g.seat.name) || "Seat",
              text: g.text,
              order: g.order
            }
          end)
      end

    opening_bookends =
      page.document["bookends"] ||
        page.document[:bookends] ||
        case page.attempts do
          [first | _] -> first.bookends
          [] -> []
        end

    page_ident = to_string(page.document["id"] || page.document[:id] || page.id)

    matching_assignment =
      Enum.find(all_assignments, fn a ->
        a.page_id == page.id or
          (a.room_id == page.room_id and to_string(a.page_identifier) == page_ident)
      end)

    matching_outcome =
      Enum.find(all_outcomes, fn o ->
        o.page_id == page.id or
          (o.room_id == page.room_id and to_string(o.page_identifier) == page_ident)
      end)

    raw_arm =
      (matching_assignment && matching_assignment.arm) ||
        (matching_outcome && matching_outcome.arm)

    experiment_id =
      (matching_assignment && matching_assignment.experiment_id) ||
        (matching_outcome && matching_outcome.experiment_id) ||
        "bait_against_plain"

    %{
      id: page.id,
      room_id: page.room_id,
      document: page.document,
      gives: formatted_gives,
      author_meta: page.author_meta,
      give: page.document["give"] || page.document[:give],
      theme: page.document["theme"] || page.document[:theme],
      chapter: page.document["chapter"] || page.document[:chapter],
      bookends: opening_bookends,
      closed_because: page.closed_because,
      melded: page.melded,
      closeness: page.closeness,
      opened_at: page.opened_at,
      closed_at: page.closed_at,
      attempts: attempts,
      recap: page_recap,
      overrules: Enum.map(page_overrules, &format_overrule/1),
      corrections: Enum.map(page_corrections, &format_correction/1),
      fairness_taps: Enum.map(page_taps, &format_fairness_tap/1),
      experiment_id: experiment_id,
      experiment_unblinded: unblinded?,
      arm: if(unblinded?, do: raw_arm, else: nil),
      trap_converged:
        if(unblinded? && matching_outcome, do: matching_outcome.trap_converged, else: nil),
      deep_converged:
        if(unblinded? && matching_outcome, do: matching_outcome.deep_converged, else: nil)
    }
  end

  # The Scribe's last word on a Page, read over by the players'. Two rows can
  # exist for one Page — the Scribe run again after a prompt changed — and the
  # book reads the later one; a correction against the recap reads over the top
  # of that, the same way a corrected Bridge does (design law 5).
  defp latest_recap(all_recaps, page, page_corrections) do
    written =
      all_recaps
      |> Enum.filter(&(&1.page_id == page.id))
      |> List.last()

    correction =
      page_corrections
      |> Enum.filter(&(&1.target == "recap"))
      |> List.last()

    cond do
      # A Page the Scribe has not got to yet, or could not write, and that
      # nobody wrote for it either. The book says so rather than showing a
      # paragraph nobody wrote.
      is_nil(written) and is_nil(correction) ->
        nil

      true ->
        written |> recap_view() |> corrected_by(correction)
    end
  end

  defp recap_view(nil), do: %{}

  defp recap_view(written) do
    %{
      id: written.id,
      recap: written.recap,
      original_recap: nil,
      corrected?: false,
      callback: written.callback,
      model: written.model,
      prompt_version: written.prompt_version,
      cost_usd: written.cost_usd,
      latency_ms: written.latency_ms,
      attempts: written.attempts,
      inserted_at: written.inserted_at
    }
  end

  defp corrected_by(view, nil), do: view

  # The players' words over the Scribe's, with the Scribe's kept underneath so
  # the book can show what was changed. A correction against a Page the Scribe
  # never wrote about is itself the paragraph: the Chronicle is theirs (design
  # law 5), and a recap they wrote from nothing is still a recap.
  defp corrected_by(view, correction) do
    Map.merge(
      %{
        id: correction.id,
        callback: nil,
        model: nil,
        prompt_version: nil,
        cost_usd: nil,
        latency_ms: nil,
        attempts: nil,
        inserted_at: correction.inserted_at
      },
      view
    )
    |> Map.merge(%{
      recap: correction.corrected_value,
      original_recap: view[:recap],
      corrected?: true
    })
  end

  defp format_fairness_tap(t) do
    closeness = t.closeness || Map.get(t, :grade)

    %{
      id: t.id,
      attempt_number: t.attempt_number,
      seat_id: t.seat_id,
      seat_name: (t.seat && t.seat.name) || "Player",
      bookends: t.bookends,
      bridges: t.bridges,
      grade: closeness,
      closeness: closeness,
      band: t.band,
      model: t.model,
      prompt_version: t.prompt_version,
      label: t.label,
      inserted_at: t.inserted_at
    }
  end

  defp format_overrule(o) do
    %{
      id: o.id,
      attempt_number: o.attempt_number,
      proposer_seat_id: o.proposer_seat_id,
      proposer_name: (o.proposer && o.proposer.name) || "Player",
      bookends: o.bookends,
      bridges: o.bridges,
      machine_closeness: o.machine_closeness,
      machine_reasoning: o.machine_reasoning,
      machine_quip: o.machine_quip,
      couple_closeness: o.couple_closeness,
      couple_reasoning: o.couple_reasoning,
      inserted_at: o.inserted_at
    }
  end

  defp format_correction(c) do
    %{
      id: c.id,
      page_id: c.page_id,
      seat_id: c.seat_id,
      author_name: (c.seat && c.seat.name) || "Player",
      attempt_number: c.attempt_number,
      target: c.target,
      original_value: c.original_value,
      corrected_value: c.corrected_value,
      note: c.note,
      inserted_at: c.inserted_at
    }
  end

  defp resolve_room_id(room_id_or_slug) do
    if is_binary(room_id_or_slug) and
         Regex.match?(
           ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
           room_id_or_slug
         ) do
      room_id_or_slug
    else
      Repo.get_by!(MeaningGame.Rooms.Room, slug: room_id_or_slug).id
    end
  end

  defp insert_page(room_id, entry, opened_at) do
    page_data = entry[:page] || %{}

    author_meta =
      Map.get(page_data, :author_meta) ||
        Map.get(page_data, "author_meta") ||
        Map.get(entry, :author_meta) ||
        Map.get(entry, "author_meta")

    page =
      %Page{}
      |> Page.changeset(%{
        room_id: room_id,
        document: page_data,
        author_meta: author_meta,
        closed_because: to_string(entry.closed_because),
        melded: entry.melded?,
        closeness: entry.closeness,
        opened_at: opened_at,
        closed_at: DateTime.utc_now()
      })
      |> Repo.insert!()

    raw_gives =
      entry[:gives] || entry["gives"] ||
        (is_map(page_data) && (page_data[:gives] || page_data["gives"]))

    gives =
      cond do
        is_list(raw_gives) ->
          raw_gives

        is_map(raw_gives) ->
          Enum.map(raw_gives, fn {s_id, txt} -> %{seat_id: s_id, text: txt} end)

        true ->
          []
      end

    gives
    |> Enum.with_index(1)
    |> Enum.each(fn {give, idx} -> insert_give(page, give, idx) end)

    page
  end

  defp insert_give(page, give, position) do
    seat_id = give[:seat_id] || give["seat_id"]
    text = give[:text] || give[:give] || give["text"] || give["give"] || ""

    if seat_id do
      %Give{}
      |> Give.changeset(%{
        page_id: page.id,
        seat_id: seat_id,
        text: text,
        order: position
      })
      |> Repo.insert!()
    end
  end

  defp insert_attempt(page, attempt) do
    row =
      %Attempt{}
      |> Attempt.changeset(%{
        page_id: page.id,
        number: attempt.number,
        bookends: attempt.bookends,
        closeness: attempt.closeness,
        melded: attempt.melded?
      })
      |> Repo.insert!()

    # The position is the order the players were shown, and it is written down
    # rather than inferred: rows inserted inside one transaction share a
    # timestamp closely enough that reading them back by it is a coin toss.
    attempt.bridges |> Enum.with_index() |> Enum.each(&insert_bridge(row, &1))
    attempt.verdicts |> Enum.with_index() |> Enum.each(&insert_verdict(row, &1))
  end

  defp insert_bridge(attempt, {bridge, position}) do
    %Bridge{}
    |> Bridge.changeset(%{
      attempt_id: attempt.id,
      seat_id: bridge.seat_id,
      bridge: bridge.bridge,
      position: position
    })
    |> Repo.insert!()
  end

  defp insert_verdict(attempt, {verdict, position}) do
    meta = verdict.meta

    %Verdict{}
    |> Verdict.changeset(%{
      attempt_id: attempt.id,
      seat_ids: verdict.seat_ids,
      bridges: verdict.bridges,
      graded: verdict.graded?,
      closeness: verdict.closeness,
      band: verdict.band && to_string(verdict.band),
      reasoning: verdict.reasoning,
      quip: verdict.quip,
      model: meta[:model],
      prompt_version: meta[:prompt_version],
      latency_ms: meta[:latency_ms],
      cost_usd: meta[:cost_usd],
      forward: meta[:forward],
      reverse: meta[:reverse],
      reasoning_reverse: meta[:reasoning_reverse],
      furthest: Map.get(verdict, :furthest),
      overruled: Map.get(verdict, :overruled?, false),
      position: position
    })
    |> Repo.insert!()
  end
end
