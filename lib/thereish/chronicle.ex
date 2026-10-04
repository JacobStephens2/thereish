defmodule Thereish.Chronicle do
  @moduledoc """
  The record of everything played, written once and never rewritten.

  A Page arrives here when it closes, as the whole thing at once: the authored
  document, every attempt in order, what each Seat wrote on each, and the one
  Verdict the Assayer gave those Bridges read together (ADR-0010). Nothing here updates a row and nothing deletes
  one — the log is the version history (ADR-0003). Retrospective opinions about
  an Assayer grade append; they do not rewrite Verdicts or Precedents (ADR-0019).
  Historical correction rows remain readable.

  Rows reference Seats and never Accounts. A Seat is permanent and claimable, so
  a history written against one comes with it whenever an Account claims it
  (ADR-0007).

  How a closed Page reads is projected by `Thereish.Chronicle.PageView`, which
  is pure over the rows loaded here: this module keeps the reads and hands each
  Page to `PageView.project/2`.

  There is no repository seam under this. Tests run against real Postgres
  through the Ecto sandbox, because a Chronicle that only ever wrote to a fake
  would prove nothing about the thing the couple are going to read.
  """

  import Ecto.Query

  alias Thereish.Chronicle.Attempt
  alias Thereish.Chronicle.Bridge
  alias Thereish.Chronicle.Correction
  alias Thereish.Chronicle.Entry
  alias Thereish.Chronicle.FairnessTap
  alias Thereish.Chronicle.Give
  alias Thereish.Chronicle.Opinion
  alias Thereish.Chronicle.Overrule
  alias Thereish.Chronicle.Page
  alias Thereish.Chronicle.PageView
  alias Thereish.Chronicle.Recap
  alias Thereish.Chronicle.Timing
  alias Thereish.Chronicle.Verdict
  alias Thereish.Experiments
  alias Thereish.Foley.Track
  alias Thereish.Foley.Vamp
  alias Thereish.Mask
  alias Thereish.Repo
  alias Thereish.Steward.TrackCache

  @doc """
  Writes one closed Page, with its attempts, its Bridges and its verdicts.

  `entry` is the `Thereish.Chronicle.Entry` the Game built when the Page
  closed, stamped with the times Pacing recorded, including `opened_at`, when
  the Room dealt the Page.

  One transaction, and every insert is a bang: a Page half in the Chronicle is
  worse than a Page that is not in it, so a row that will not go in takes the
  whole write down rather than leaving a torn record behind.
  """
  @spec write(Ecto.UUID.t(), Entry.t()) :: {:ok, Page.t()}
  def write(room_id, %Entry{} = entry) do
    Repo.transaction(fn ->
      page = insert_page(room_id, entry)

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
  Correction writes are retired. Historical correction rows remain readable
  (ADR-0019).
  """
  @spec record_correction(Ecto.UUID.t(), map()) :: {:error, :corrections_retired}
  def record_correction(_room_id, _attrs), do: {:error, :corrections_retired}

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
  Records one retrospective opinion about an Attempt's original Assayer grade.

  Original participants are Seats that wrote a Bridge on that Attempt. The
  authenticated admin may review any Attempt, attributed separately. Opinions
  append; they do not rewrite the Verdict, an overrule, or a cached Precedent
  (ADR-0006, ADR-0019).
  """
  @spec record_opinion(Ecto.UUID.t() | String.t(), map()) ::
          {:ok, FairnessTap.t()} | {:error, atom() | Ecto.Changeset.t()}
  def record_opinion(room_id, attrs) do
    room_id = resolve_room_id(room_id)
    reviewer = Map.get(attrs, :as) || Map.get(attrs, "as")

    with {:ok, graded} <- opinion_target(room_id, attrs),
         :ok <- known_admin(reviewer),
         {:ok, opinion} <-
           Opinion.new(graded, reviewer, Map.get(attrs, :label) || Map.get(attrs, "label")) do
      record_fairness_tap(room_id, opinion)
    end
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

    Opinion.calibration(taps)
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
    |> Repo.preload([:gives, attempts: [:bridges, :verdicts]])
  end

  @doc """
  Every Room, newest first, with how many Pages it has closed.

  Operator discovery: a Code is not a prerequisite for finding a Room.
  """
  @spec admin_rooms() :: [map()]
  def admin_rooms do
    from(r in Thereish.Rooms.Room,
      left_join: p in Page,
      on: p.room_id == r.id,
      group_by: [r.id, r.slug, r.inserted_at],
      order_by: [desc: r.inserted_at, desc: r.id],
      select: %{
        id: r.id,
        slug: r.slug,
        opened_at: r.inserted_at,
        pages_count: count(p.id),
        last_closed_at: max(p.closed_at)
      }
    )
    |> Repo.all()
  end

  @doc """
  Duration readouts for closed Pages, newest first.

  Exact totals end at the final reveal. Pages written before occurrence
  times were recorded are labelled as estimates.
  """
  @spec page_timings() :: [Timing.t()]
  def page_timings do
    timing_pages()
    |> Repo.all()
    |> Enum.map(&Timing.view/1)
  end

  @spec page_timings(String.t()) :: [Timing.t()]
  def page_timings(slug) when is_binary(slug) do
    case Thereish.Rooms.get_room(slug) do
      nil ->
        []

      room ->
        timing_pages()
        |> where([p], p.room_id == ^room.id)
        |> Repo.all()
        |> Enum.map(&Timing.view/1)
    end
  end

  @doc """
  Returns true if the Room has at least one Page written in its Chronicle.
  """
  @spec has_pages?(Ecto.UUID.t()) :: boolean()
  def has_pages?(room_id) do
    from(p in Page, where: p.room_id == ^room_id, select: 1, limit: 1)
    |> Repo.exists?()
  end

  @doc """
  Computes the book view from the event log for one Room, in reverse
  chronological order (newest Page first).

  No stored copy of a view exists anywhere (design law 5, ADR-0003). The view is
  projected directly from the append-only rows: Pages, attempts, bridges, verdicts,
  overrules, and corrections.
  """
  @spec book(Ecto.UUID.t() | String.t()) :: [PageView.t()]
  def book(room_id_or_slug), do: page_views(room_id_or_slug, :desc)

  @doc """
  Computes views of all Pages in one Room directly from the event log, in the
  given order (:asc or :desc).
  """
  @spec page_views(Ecto.UUID.t() | String.t(), :asc | :desc) :: [PageView.t()]
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

    rows = %{
      overrules: overrules(room_id),
      corrections: corrections(room_id),
      fairness_taps: fairness_taps(room_id),
      recaps: recaps(room_id),
      page_arms: Experiments.page_arms(room_id)
    }

    Enum.map(pages, &PageView.project(&1, rows))
  end

  @doc """
  Renders the Chronicle for a Room as a Markdown document on demand.
  """
  @spec to_markdown(Ecto.UUID.t() | String.t()) :: String.t()
  def to_markdown(room_id_or_slug), do: Thereish.Chronicle.Markdown.render(room_id_or_slug)

  @doc """
  Parses an exported Chronicle Markdown document back into structured data.
  """
  @spec from_markdown(String.t()) :: {:ok, [map()]} | {:error, term()}
  def from_markdown(markdown), do: Thereish.Chronicle.Markdown.parse(markdown)

  @doc """
  Replaces the Track on an existing Chronicle page.
  """
  @spec replace_page_music(Ecto.UUID.t() | Page.t(), Track.t()) ::
          {:ok, Page.t()} | {:error, term()}
  def replace_page_music(page, music_meta), do: replace_page_field(page, :music_meta, music_meta)

  @doc """
  Replaces the Vamp on an existing Chronicle page.
  """
  @spec replace_page_vamp(Ecto.UUID.t() | Page.t(), Vamp.t()) ::
          {:ok, Page.t()} | {:error, term()}
  def replace_page_vamp(page, vamp_meta), do: replace_page_field(page, :vamp_meta, vamp_meta)

  @doc """
  Replaces the masks_meta on an existing Chronicle page with the latest masks record.
  """
  @spec replace_page_masks(Ecto.UUID.t() | Page.t(), %{String.t() => Mask.t() | :dot}) ::
          {:ok, Page.t()} | {:error, term()}
  def replace_page_masks(page, masks_meta), do: replace_page_field(page, :masks_meta, masks_meta)

  @doc """
  Updates or adds a single seat's mask on a Page's masks_meta.
  """
  @spec update_page_mask(Ecto.UUID.t() | Page.t(), String.t(), Mask.t() | :dot) ::
          {:ok, Page.t()} | {:error, term()}
  def update_page_mask(%Page{} = page, seat_id, mask) do
    replace_page_masks(page, Map.put(page.masks_meta || %{}, seat_id, mask))
  end

  def update_page_mask(page_id, seat_id, mask) when is_binary(page_id) do
    case Repo.get(Page, page_id) do
      nil -> {:error, :not_found}
      page -> update_page_mask(page, seat_id, mask)
    end
  end

  defp replace_page_field(%Page{} = page, field, value) do
    page
    |> Page.changeset(%{field => value})
    |> Repo.update()
  end

  defp replace_page_field(page_id, field, value) when is_binary(page_id) do
    case Repo.get(Page, page_id) do
      nil -> {:error, :not_found}
      page -> replace_page_field(page, field, value)
    end
  end

  @doc """
  Retained generated media across Rooms, for the operator gallery.

  Assembles Tracks from the track cache and Page music records, Vamps from Page
  vamp records, and Masks from Page mask records. A Room or Page is named only
  when the record actually belongs to one; missing files are marked present or
  not rather than deleted.
  """
  @spec gallery() :: %{tracks: [map()], vamps: [map()], masks: [map()]}
  def gallery do
    pages =
      from(p in Page, preload: [:room], order_by: [desc: p.closed_at])
      |> Repo.all()

    cache_rows = Repo.all(from(t in TrackCache, order_by: [desc: t.inserted_at]))

    track_hits =
      for %Page{music_meta: track} = page <- pages, Track.kept?(track) do
        {track.path, page, %{title: track.title, loop: false}}
      end

    vamp_hits =
      for %Page{vamp_meta: vamp} = page <- pages, Vamp.kept?(vamp) do
        {vamp.path, page, %{title: nil, loop: vamp.loop not in [nil, false]}}
      end

    %{
      tracks: gallery_audio(track_hits, cache_rows),
      vamps: gallery_audio(vamp_hits, []),
      masks: gallery_masks(pages)
    }
  end

  # Each hit is a kept record's `{path, page, %{title, loop}}`.
  defp gallery_audio(page_hits, cache_rows) do
    by_path = Enum.group_by(page_hits, &elem(&1, 0))
    cache_by_path = Map.new(cache_rows, &{&1.path, &1})

    paths =
      (Enum.map(cache_rows, & &1.path) ++ Enum.map(page_hits, &elem(&1, 0)))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    Enum.map(paths, fn path ->
      hits = Map.get(by_path, path, [])
      cache = cache_by_path[path]

      first =
        case hits do
          [{_path, _page, record} | _] -> record
          _ -> %{title: nil, loop: false}
        end

      %{
        path: path,
        title: (cache && cache.title) || first.title,
        loop: first.loop,
        present?: TrackCache.file_exists?(path),
        associations: Enum.map(hits, fn {_path, page, _meta} -> gallery_association(page) end)
      }
    end)
  end

  defp gallery_masks(pages) do
    hits =
      for page <- pages,
          is_map(page.masks_meta),
          {_seat, mask} <- page.masks_meta,
          url = Mask.url(mask),
          is_binary(url) and url != "" do
        {url, page}
      end

    hits
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {url, assoc_pages} ->
      %{
        url: url,
        present?: TrackCache.file_exists?(url),
        associations: Enum.map(assoc_pages, &gallery_association/1)
      }
    end)
  end

  defp gallery_association(page) do
    %{
      room_slug: page.room.slug,
      bookends: page.document.bookends
    }
  end

  defp opinion_target(room_id, attrs) do
    page_id = Map.get(attrs, :page_id) || Map.get(attrs, "page_id")
    attempt_number = Map.get(attrs, :attempt_number) || Map.get(attrs, "attempt_number")

    page =
      if is_binary(page_id) do
        Page
        |> Repo.get(page_id)
        |> Repo.preload(attempts: [:bridges, :verdicts])
      end

    attempt = page && Enum.find(page.attempts, &(&1.number == attempt_number))

    cond do
      is_nil(page) or page.room_id != room_id or is_nil(attempt) ->
        {:error, :no_such_attempt}

      true ->
        overrule =
          Enum.find(overrules(room_id), &PageView.about_attempt?(&1, page, attempt))

        verdict = List.first(attempt.verdicts)

        {:ok,
         %{
           page_id: page.id,
           attempt_number: attempt.number,
           bookends: attempt.bookends,
           bridges: Enum.map(attempt.bridges, & &1.bridge),
           participant_ids: Enum.map(attempt.bridges, & &1.seat_id),
           closeness: verdict && verdict.closeness,
           machine_closeness: overrule && overrule.machine_closeness,
           band: verdict && verdict.band,
           model: verdict && verdict.model,
           prompt_version: verdict && verdict.prompt_version
         }}
    end
  end

  # The admin may review any Attempt, but only an admin identity that exists.
  # Any other reviewer is left to `Opinion.new/3`.
  defp known_admin({:admin, admin_id}) when is_binary(admin_id) do
    case Repo.get(Thereish.Admin.Identity, admin_id) do
      %Thereish.Admin.Identity{} -> :ok
      nil -> {:error, :not_admin}
    end
  end

  defp known_admin(_reviewer), do: :ok

  defp uuid?(val) when is_binary(val) do
    Regex.match?(
      ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
      val
    )
  end

  defp uuid?(_), do: false

  defp resolve_room_id(room_id_or_slug) do
    if uuid?(room_id_or_slug) do
      room_id_or_slug
    else
      Repo.get_by!(Thereish.Rooms.Room, slug: room_id_or_slug).id
    end
  end

  defp timing_pages do
    from(p in Page,
      join: r in assoc(p, :room),
      order_by: [desc: p.closed_at, desc: p.id],
      preload: [:gives, :attempts, :room]
    )
  end

  defp insert_page(room_id, %Entry{} = entry) do
    page =
      %Page{}
      |> Page.changeset(%{
        room_id: room_id,
        document: entry.page,
        author_meta: entry.author_meta,
        music_meta: entry.music_meta,
        vamp_meta: entry.vamp_meta,
        masks_meta: entry.masks,
        closed_because: to_string(entry.closed_because),
        melded: entry.melded?,
        closeness: entry.closeness,
        opened_at: entry.opened_at,
        closed_at: DateTime.utc_now(),
        revealed_at: entry.revealed_at
      })
      |> Repo.insert!()

    entry.gives
    |> Enum.with_index(1)
    |> Enum.each(fn {give, idx} -> insert_give(page, give, idx) end)

    page
  end

  defp insert_give(page, %Entry.Give{} = give, position) do
    %Give{}
    |> Give.changeset(%{
      page_id: page.id,
      seat_id: give.seat_id,
      text: give.text,
      order: position,
      arrived_at: give.arrived_at
    })
    |> Repo.insert!()
  end

  defp insert_attempt(page, %Entry.Attempt{} = attempt) do
    row =
      %Attempt{}
      |> Attempt.changeset(%{
        page_id: page.id,
        number: attempt.number,
        bookends: attempt.bookends,
        closeness: attempt.closeness,
        melded: attempt.melded?,
        started_at: attempt.started_at,
        assaying_started_at: attempt.assaying_started_at,
        revealed_at: attempt.revealed_at,
        advanced_at: attempt.advanced_at
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

  defp insert_verdict(attempt, {%Entry.Verdict{} = verdict, position}) do
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
      furthest: verdict.furthest,
      overruled: verdict.overruled?,
      position: position,
      voice_meta: verdict.voice_meta
    })
    |> Repo.insert!()
  end
end
