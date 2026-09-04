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

    Enum.map(pages, &compute_page_view(&1, all_overrules, all_corrections))
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

    lines = [
      "Page #{index} (#{anchors_str}) — #{outcome_str}"
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

  @doc """
  Computes the view of one Page from its event rows, overrules, and corrections.
  """
  def compute_page_view(%Page{} = page, all_overrules, all_corrections) do
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
          corrections: Enum.map(attempt_corrections, &format_correction/1)
        }
      end)

    opening_anchors =
      page.document["anchors"] ||
        case page.attempts do
          [first | _] -> first.anchors
          [] -> []
        end

    %{
      id: page.id,
      room_id: page.room_id,
      document: page.document,
      anchors: opening_anchors,
      closed_because: page.closed_because,
      melded: page.melded,
      closeness: page.closeness,
      opened_at: page.opened_at,
      closed_at: page.closed_at,
      attempts: attempts,
      overrules: Enum.map(page_overrules, &format_overrule/1),
      corrections: Enum.map(page_corrections, &format_correction/1)
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
