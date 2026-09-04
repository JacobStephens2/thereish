defmodule MeaningGame.Chronicle do
  @moduledoc """
  The record of everything played, written once and never rewritten.

  A Page arrives here when it closes, as the whole thing at once: the authored
  document, every attempt in order, what each Seat wrote on each, and what the
  Assayer said about each pair. Nothing here updates a row and nothing deletes
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
  alias MeaningGame.Chronicle.Overrule
  alias MeaningGame.Chronicle.Page
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
        attempts: [:verdicts, bridges: :seat],
        overrules: :proposer,
        corrections: :seat
      )

    all_overrules = overrules(room_id)
    all_corrections = corrections(room_id)
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
  Composes a concise digest of the Chronicle for feeding to models.

  Returns a default message if no Pages have been played yet.
  """
  @spec digest(Ecto.UUID.t() | String.t()) :: String.t()
  def digest(room_id_or_slug) do
    views = page_views(room_id_or_slug, :asc)

    if views == [] do
      "Nothing yet; this is the first Page."
    else
      views
      |> Enum.with_index(1)
      |> Enum.map(&digest_page/1)
      |> Enum.join("\n\n")
    end
  end

  defp digest_page({page, index}) do
    anchors_str = Enum.join(page.anchors, " · ")

    last_attempt = List.last(page.attempts)
    last_verdict = last_attempt && List.first(last_attempt.verdicts)

    outcome_str =
      if page.melded do
        band_str = (last_verdict && last_verdict.band && ", #{last_verdict.band}") || ""
        "Melded on attempt #{last_attempt.number} (closeness: #{page.closeness}#{band_str})"
      else
        "Unmelded after #{length(page.attempts)} attempts"
      end

    give_str = if page[:give], do: " [Give: #{page.give}]", else: ""

    lines = [
      "Page #{index} (#{anchors_str})#{give_str} — #{outcome_str}"
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

    Enum.join(lines ++ attempt_lines ++ overrule_lines ++ correction_lines, "\n")
  end

  def compute_page_view(
        %Page{} = page,
        all_overrules,
        all_corrections,
        all_taps \\ [],
        all_assignments \\ [],
        all_outcomes \\ [],
        unblinded? \\ false
      ) do
    page_overrules =
      Enum.filter(all_overrules, fn o ->
        o.page_id == page.id or
          (o.room_id == page.room_id and
             Enum.any?(
               page.attempts,
               &(&1.number == o.attempt_number and &1.anchors == o.anchors)
             ))
      end)

    page_corrections =
      Enum.filter(all_corrections, fn c ->
        c.page_id == page.id
      end)

    page_taps =
      Enum.filter(all_taps, fn t ->
        t.page_id == page.id or
          (t.room_id == page.room_id and
             Enum.any?(
               page.attempts,
               &(&1.number == t.attempt_number and &1.anchors == t.anchors)
             ))
      end)

    attempts =
      Enum.map(page.attempts, fn attempt ->
        attempt_overrules =
          Enum.filter(page_overrules, fn o ->
            o.attempt_number == attempt.number and
              (o.anchors == attempt.anchors or o.page_id == page.id)
          end)

        attempt_corrections =
          Enum.filter(page_corrections, fn c ->
            c.attempt_number == attempt.number
          end)

        attempt_taps =
          Enum.filter(page_taps, fn t ->
            t.attempt_number == attempt.number and
              (t.anchors == attempt.anchors or t.page_id == page.id)
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
              position: v.position
            }
          end)

        %{
          id: attempt.id,
          number: attempt.number,
          anchors: attempt.anchors,
          closeness: attempt.closeness,
          melded: attempt.melded,
          bridges: bridges,
          verdicts: verdicts,
          overrules: Enum.map(attempt_overrules, &format_overrule/1),
          corrections: Enum.map(attempt_corrections, &format_correction/1),
          fairness_taps: Enum.map(attempt_taps, &format_fairness_tap/1)
        }
      end)

    opening_anchors =
      page.document["anchors"] ||
        case page.attempts do
          [first | _] -> first.anchors
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
      give: page.document["give"] || page.document[:give],
      theme: page.document["theme"] || page.document[:theme],
      chapter: page.document["chapter"] || page.document[:chapter],
      anchors: opening_anchors,
      closed_because: page.closed_because,
      melded: page.melded,
      closeness: page.closeness,
      opened_at: page.opened_at,
      closed_at: page.closed_at,
      attempts: attempts,
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

  defp format_fairness_tap(t) do
    closeness = t.closeness || Map.get(t, :grade)

    %{
      id: t.id,
      attempt_number: t.attempt_number,
      seat_id: t.seat_id,
      seat_name: (t.seat && t.seat.name) || "Player",
      anchors: t.anchors,
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
      anchors: o.anchors,
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
    %Page{}
    |> Page.changeset(%{
      room_id: room_id,
      document: entry.page,
      closed_because: to_string(entry.closed_because),
      melded: entry.melded?,
      closeness: entry.closeness,
      opened_at: opened_at,
      closed_at: DateTime.utc_now()
    })
    |> Repo.insert!()
  end

  defp insert_attempt(page, attempt) do
    row =
      %Attempt{}
      |> Attempt.changeset(%{
        page_id: page.id,
        number: attempt.number,
        anchors: attempt.anchors,
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
      overruled: Map.get(verdict, :overruled?, false),
      position: position
    })
    |> Repo.insert!()
  end
end
