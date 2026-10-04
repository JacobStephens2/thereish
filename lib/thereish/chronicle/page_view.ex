defmodule Thereish.Chronicle.PageView do
  @moduledoc """
  How one closed Page reads: in the book, in the Markdown export, in the
  Scribe's prompt and in an Experiment's readout.

  Pure over rows the Chronicle has already loaded. `project/2` takes a `%Page{}`
  with its gives, attempts, bridges, verdicts, overrules and corrections
  preloaded, plus the Room's overrules, corrections, fairness taps, recaps and
  experiment rows, and answers the view. Nothing is stored: the view is
  projected on demand from the append-only rows every time it is read
  (ADR-0003). The players' recap and corrections read over the Scribe's and the
  Assayer's without rewriting either (ADR-0019).

  This is not a seam over Postgres. The Chronicle keeps the reads; this module
  only decides what they mean, so every rule about how a Page reads can be
  tested from in-memory structs.
  """

  alias Thereish.Bookends
  alias Thereish.Chronicle.Attempt
  alias Thereish.Chronicle.Correction
  alias Thereish.Chronicle.FairnessTap
  alias Thereish.Chronicle.Opinion
  alias Thereish.Chronicle.Overrule
  alias Thereish.Chronicle.Page
  alias Thereish.Chronicle.Recap
  alias Thereish.Experiments
  alias Thereish.Foley.Track
  alias Thereish.Foley.Vamp
  alias Thereish.Mask

  @typedoc """
  The Room's rows a Page reads against, each oldest first, plus the Room's
  `Experiments.page_arms/1`.
  """
  @type rows :: %{
          overrules: [Overrule.t()],
          corrections: [Correction.t()],
          fairness_taps: [FairnessTap.t()],
          recaps: [Recap.t()],
          page_arms: Experiments.page_arms()
        }

  @typedoc """
  One Give, under the Mask its Seat wore. A Give from a Page written before Give
  rows has no id, no Seat, no Seat name and no Mask.
  """
  @type give_view :: %{
          id: Ecto.UUID.t() | nil,
          seat_id: Ecto.UUID.t() | nil,
          seat_name: String.t() | nil,
          text: String.t(),
          order: integer(),
          mask: Mask.t() | nil
        }

  @typedoc """
  A Mask whose Seat gave nothing on the Page, named from that Seat's Bridges on
  the Page when it has any.
  """
  @type mask_without_give :: %{
          seat_id: Ecto.UUID.t(),
          seat_name: String.t() | nil,
          mask: Mask.t()
        }

  @typedoc "The Track a Page kept, when it has a title."
  @type track_view :: %{path: String.t(), title: String.t()}

  @typedoc "The Vamp a Page kept."
  @type vamp_view :: %{path: String.t(), duration: integer() | nil, loop: boolean()}

  @typedoc "One Bridge, read through the latest correction against it."
  @type bridge_view :: %{
          id: Ecto.UUID.t(),
          seat_id: Ecto.UUID.t() | nil,
          seat_name: String.t(),
          bridge: String.t(),
          original_bridge: String.t() | nil,
          corrected?: boolean(),
          position: integer()
        }

  @typedoc "One Verdict, marked overruled when any overrule is about its Attempt."
  @type verdict_view :: %{
          id: Ecto.UUID.t(),
          seat_ids: [Ecto.UUID.t()],
          bridges: [String.t()],
          graded: boolean(),
          closeness: integer() | nil,
          band: String.t() | nil,
          reasoning: String.t() | nil,
          quip: String.t() | nil,
          overruled: boolean(),
          model: String.t() | nil,
          prompt_version: String.t() | nil,
          latency_ms: integer() | nil,
          cost_usd: Decimal.t() | nil,
          forward: integer() | nil,
          reverse: integer() | nil,
          reasoning_reverse: String.t() | nil,
          furthest: [String.t()] | nil,
          position: integer()
        }

  @typedoc "One overrule, with what the machine said and what the couple said."
  @type overrule_view :: %{
          id: Ecto.UUID.t(),
          attempt_number: integer(),
          proposer_seat_id: Ecto.UUID.t(),
          proposer_name: String.t(),
          bookends: [String.t()],
          bridges: [String.t()],
          machine_closeness: integer() | nil,
          machine_reasoning: String.t() | nil,
          machine_quip: String.t() | nil,
          couple_closeness: integer(),
          couple_reasoning: String.t(),
          inserted_at: DateTime.t()
        }

  @typedoc "One historical correction, and who wrote it."
  @type correction_view :: %{
          id: Ecto.UUID.t(),
          page_id: Ecto.UUID.t() | nil,
          seat_id: Ecto.UUID.t() | nil,
          author_name: String.t(),
          attempt_number: integer() | nil,
          target: String.t(),
          original_value: String.t() | nil,
          corrected_value: String.t(),
          note: String.t() | nil,
          inserted_at: DateTime.t()
        }

  @typedoc "One opinion about an Assayer grade, from a participant or the admin."
  @type tap_view :: %{
          id: Ecto.UUID.t(),
          attempt_number: integer(),
          seat_id: Ecto.UUID.t() | nil,
          admin_id: Ecto.UUID.t() | nil,
          source: String.t(),
          seat_name: String.t() | nil,
          reviewer_name: String.t(),
          bookends: [String.t()],
          bridges: [String.t()],
          grade: integer() | nil,
          closeness: integer() | nil,
          band: String.t() | nil,
          model: String.t() | nil,
          prompt_version: String.t() | nil,
          label: String.t(),
          inserted_at: DateTime.t()
        }

  @typedoc "One Attempt, with the rows about it."
  @type attempt_view :: %{
          id: Ecto.UUID.t(),
          number: integer(),
          bookends: [String.t()],
          closeness: integer() | nil,
          melded: boolean(),
          bridges: [bridge_view()],
          participant_ids: [Ecto.UUID.t()],
          verdicts: [verdict_view()],
          carried: [String.t()] | nil,
          bookend_chips: [Bookends.chip()],
          overrules: [overrule_view()],
          corrections: [correction_view()],
          fairness_taps: [tap_view()]
        }

  @typedoc "The Scribe's recap, or the players' correction read over it."
  @type recap_view :: %{
          id: Ecto.UUID.t(),
          recap: String.t(),
          original_recap: String.t() | nil,
          corrected?: boolean(),
          callback: String.t() | nil,
          model: String.t() | nil,
          prompt_version: String.t() | nil,
          cost_usd: float() | nil,
          latency_ms: integer() | nil,
          attempts: integer() | nil,
          inserted_at: DateTime.t()
        }

  @type t :: %__MODULE__{
          id: Ecto.UUID.t(),
          room_id: Ecto.UUID.t(),
          document: map(),
          gives: [give_view()],
          masks_without_give: [mask_without_give()],
          author_meta: map() | nil,
          track: track_view() | nil,
          vamp: vamp_view() | nil,
          bookends: [String.t()],
          bookend_origins: [Bookends.origin()],
          full_table: boolean() | nil,
          closed_because: String.t(),
          melded: boolean(),
          closeness: integer() | nil,
          opened_at: DateTime.t(),
          closed_at: DateTime.t(),
          attempts: [attempt_view()],
          recap: recap_view() | nil,
          overrules: [overrule_view()],
          corrections: [correction_view()],
          fairness_taps: [tap_view()],
          experiment_id: String.t(),
          experiment_unblinded: boolean(),
          arm: String.t() | nil,
          trap_converged: boolean() | nil,
          deep_converged: boolean() | nil
        }

  defstruct [
    :id,
    :room_id,
    :document,
    :author_meta,
    :track,
    :vamp,
    :full_table,
    :closed_because,
    :melded,
    :closeness,
    :opened_at,
    :closed_at,
    :recap,
    :experiment_id,
    :arm,
    :trap_converged,
    :deep_converged,
    gives: [],
    masks_without_give: [],
    bookends: [],
    bookend_origins: [],
    attempts: [],
    overrules: [],
    corrections: [],
    fairness_taps: [],
    experiment_unblinded: false
  ]

  @doc """
  Projects one closed Page against its Room's rows.

  A Page's own overrules and fairness taps are every row that names the Page
  plus every row about one of its Attempts (`about_attempt?/3`). Of the fairness
  taps, only each reviewer's current Opinion is shown (`Opinion.current/1`).
  Its corrections are the rows that name it.
  """
  @spec project(Page.t(), rows()) :: t()
  def project(%Page{} = page, rows) do
    of_page? = fn row ->
      row.page_id == page.id or Enum.any?(page.attempts, &about_attempt?(row, page, &1))
    end

    own = %{
      overrules: Enum.filter(rows.overrules, of_page?),
      corrections: Enum.filter(rows.corrections, &(&1.page_id == page.id)),
      fairness_taps: rows.fairness_taps |> Enum.filter(of_page?) |> Opinion.current()
    }

    attempts =
      page.attempts
      |> Enum.with_index()
      |> Enum.map(fn {attempt, index} -> attempt_view(page, attempt, index, own) end)

    %__MODULE__{
      id: page.id,
      room_id: page.room_id,
      document: page.document,
      gives: gives(page),
      masks_without_give: masks_without_give(page),
      author_meta: page.author_meta,
      track: track(page.music_meta),
      vamp: vamp(page.vamp_meta),
      bookends: opening_bookends(page),
      bookend_origins: Bookends.origins(page.document),
      full_table: full_table(page.document),
      closed_because: page.closed_because,
      melded: page.melded,
      closeness: page.closeness,
      opened_at: page.opened_at,
      closed_at: page.closed_at,
      attempts: attempts,
      recap: latest_recap(rows.recaps, page, own.corrections),
      overrules: Enum.map(own.overrules, &overrule_view/1),
      corrections: Enum.map(own.corrections, &correction_view/1),
      fairness_taps: Enum.map(own.fairness_taps, &tap_view/1)
    }
    |> struct!(Experiments.page_arm(rows.page_arms, page))
  end

  @doc """
  Whether an overrule or fairness-tap row is about one Attempt of a Page.

  The Attempt numbers match, and either the row names this Page or it is from
  the same Room with the same Bookends. The second arm reads rows written before
  rows named their Page.
  """
  @spec about_attempt?(Overrule.t() | FairnessTap.t(), Page.t(), Attempt.t()) :: boolean()
  def about_attempt?(row, %Page{} = page, attempt) do
    row.attempt_number == attempt.number and
      (row.page_id == page.id or
         (row.room_id == page.room_id and row.bookends == attempt.bookends))
  end

  # `own` holds the Page's own overrules, corrections and fairness taps.
  defp attempt_view(page, attempt, index, own) do
    attempt_overrules = Enum.filter(own.overrules, &about_attempt?(&1, page, attempt))
    attempt_corrections = Enum.filter(own.corrections, &(&1.attempt_number == attempt.number))
    attempt_taps = Enum.filter(own.fairness_taps, &about_attempt?(&1, page, attempt))

    bridges = Enum.map(attempt.bridges, &bridge_view(&1, attempt, own.corrections))
    verdicts = Enum.map(attempt.verdicts, &verdict_view(&1, attempt_overrules != []))

    %{
      id: attempt.id,
      number: attempt.number,
      bookends: attempt.bookends,
      closeness: attempt.closeness,
      melded: attempt.melded,
      bridges: bridges,
      participant_ids: Enum.map(attempt.bridges, & &1.seat_id),
      verdicts: verdicts,
      carried: carried(page, index, attempt),
      bookend_chips: bookend_chips(page, attempt, index),
      overrules: Enum.map(attempt_overrules, &overrule_view/1),
      corrections: Enum.map(attempt_corrections, &correction_view/1),
      fairness_taps: Enum.map(attempt_taps, &tap_view/1)
    }
  end

  defp bridge_view(b, attempt, page_corrections) do
    correction =
      page_corrections
      |> Enum.filter(fn c ->
        c.target == "bridge" and
          (c.attempt_number == attempt.number or is_nil(c.attempt_number)) and
          ((c.original_value && c.original_value == b.bridge) or
             ((c.attempt_number == attempt.number and c.seat_id) && c.seat_id == b.seat_id))
      end)
      |> List.last()

    view = %{
      id: b.id,
      seat_id: b.seat_id,
      seat_name: seat_name(b.seat, "Player"),
      bridge: b.bridge,
      original_bridge: nil,
      corrected?: false,
      position: b.position
    }

    if correction do
      %{view | bridge: correction.corrected_value, original_bridge: b.bridge, corrected?: true}
    else
      view
    end
  end

  defp verdict_view(v, overruled_by_players?) do
    %{
      id: v.id,
      seat_ids: v.seat_ids,
      bridges: v.bridges,
      graded: v.graded,
      closeness: v.closeness,
      band: v.band,
      reasoning: v.reasoning,
      quip: v.quip,
      overruled: v.overruled || overruled_by_players?,
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
  end

  defp give_view(g, masks) do
    %{
      id: g.id,
      seat_id: g.seat_id,
      seat_name: seat_name(g.seat, "Seat"),
      text: g.text,
      order: g.order,
      mask: Map.get(masks, g.seat_id)
    }
  end

  # A Page written before Give rows kept its one Give in its document, with no
  # Seat. It reads as that one Give, so no reader branches on a Page's vintage
  # (ADR-0003).
  defp gives(%Page{gives: [], document: doc}) do
    case doc["give"] || doc[:give] do
      nil -> []
      text -> [%{id: nil, seat_id: nil, seat_name: nil, text: text, order: 0, mask: nil}]
    end
  end

  defp gives(page), do: Enum.map(page.gives, &give_view(&1, page.masks_meta || %{}))

  # A Mask reads on its Seat's Give. Only a Mask with a picture whose Seat gave
  # nothing on the Page is listed apart, named from that Seat's Bridges.
  defp masks_without_give(page) do
    gave = MapSet.new(page.gives, & &1.seat_id)

    for {seat_id, mask} <- page.masks_meta || %{},
        Mask.url(mask),
        not MapSet.member?(gave, seat_id) do
      %{seat_id: seat_id, seat_name: bridge_seat_name(page, seat_id), mask: mask}
    end
  end

  defp bridge_seat_name(page, seat_id) do
    Enum.find_value(page.attempts, fn attempt ->
      Enum.find_value(attempt.bridges, &((&1.seat_id == seat_id and &1.seat) && &1.seat.name))
    end)
  end

  # The book shows only a titled Track the Page kept.
  defp track(%Track{title: title} = track) when is_binary(title) and title != "" do
    if Track.kept?(track), do: %{path: track.path, title: title}
  end

  defp track(_other), do: nil

  defp vamp(vamp) do
    if Vamp.kept?(vamp) do
      %{path: vamp.path, duration: vamp.duration, loop: vamp.loop not in [nil, false]}
    end
  end

  defp opening_bookends(page) do
    page.document["bookends"] ||
      page.document[:bookends] ||
      case page.attempts do
        [first | _] -> first.bookends
        [] -> []
      end
  end

  # The words a missed Attempt handed on: the next Attempt's Bookends when there
  # was one, else what the table's rule carries (`Bookends.carry/3`) from the
  # Bridges as the table played them, before any correction (ADR-0019). An
  # Attempt that never reached a Verdict was never revealed, so the table
  # carried nothing from it.
  defp carried(page, index, attempt) do
    next = Enum.at(page.attempts, index + 1)

    cond do
      attempt.melded == true ->
        nil

      is_map(next) ->
        next.bookends

      attempt.verdicts == [] ->
        nil

      true ->
        [first | _] = attempt.verdicts
        verdict = %{graded?: first.graded, furthest: first.furthest}

        recorded_bridges(attempt)
        |> Bookends.carry(verdict, full_table(page.document) == true)
        |> Map.fetch!(:carried)
        |> Enum.map(& &1.word)
    end
  end

  defp recorded_bridges(attempt) do
    Enum.map(attempt.bridges || [], &%{seat_id: &1.seat_id, bridge: &1.bridge})
  end

  defp full_table(doc) when is_map(doc) do
    case Map.get(doc, "full_table", Map.get(doc, :full_table)) do
      true -> true
      false -> false
      _ -> nil
    end
  end

  defp full_table(_), do: nil

  # A first-Attempt chip names the Give its word came from and wears no Mask,
  # even when its origin names a Seat. A later chip claims the Bridge it carried
  # from the Attempt before, at most once per Bridge, and wears that Seat's Mask.
  defp bookend_chips(page, attempt, index) do
    words = attempt.bookends || []

    origins =
      if attempt.number == 1 do
        Bookends.origins(page.document)
      else
        prev = if index > 0, do: Enum.at(page.attempts, index - 1)
        Bookends.claim(words, (prev && recorded_bridges(prev)) || [])
      end

    Bookends.chips(words, origins, attempt.number, page.masks_meta || %{})
  end

  # The Scribe's last word on a Page, read over by the players'. Two rows can
  # exist for one Page — the Scribe run again after a prompt changed — and the
  # book reads the later one; a correction against the recap reads over the top
  # of that, the same way a corrected Bridge does (design law 5).
  defp latest_recap(recaps, page, page_corrections) do
    written = recaps |> Enum.filter(&(&1.page_id == page.id)) |> List.last()

    correction =
      page_corrections
      |> Enum.filter(&(&1.target == "recap"))
      |> List.last()

    recap_view(written, correction)
  end

  # A Page the Scribe has not got to yet, or could not write, and that nobody
  # wrote for it either. The book says so rather than showing a paragraph nobody
  # wrote.
  defp recap_view(nil, nil), do: nil

  defp recap_view(written, nil) do
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

  # A correction against a Page the Scribe never wrote about is itself the
  # paragraph: the Chronicle is theirs (design law 5), and a recap they wrote
  # from nothing is still a recap.
  defp recap_view(nil, correction) do
    %{
      id: correction.id,
      recap: correction.corrected_value,
      original_recap: nil,
      corrected?: true,
      callback: nil,
      model: nil,
      prompt_version: nil,
      cost_usd: nil,
      latency_ms: nil,
      attempts: nil,
      inserted_at: correction.inserted_at
    }
  end

  # The players' words over the Scribe's, with the Scribe's kept underneath so
  # the book can show what was changed.
  defp recap_view(written, correction) do
    %{
      recap_view(written, nil)
      | recap: correction.corrected_value,
        original_recap: written.recap,
        corrected?: true
    }
  end

  defp tap_view(t) do
    closeness = t.closeness || Map.get(t, :grade)
    source = Map.get(t, :source) || "participant"

    %{
      id: t.id,
      attempt_number: t.attempt_number,
      seat_id: t.seat_id,
      admin_id: Map.get(t, :admin_id),
      source: source,
      seat_name: t.seat && t.seat.name,
      reviewer_name: opinion_reviewer_name(t, source),
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

  defp opinion_reviewer_name(_t, "admin"), do: "Admin"
  defp opinion_reviewer_name(t, _), do: seat_name(t.seat, "Player")

  defp overrule_view(o) do
    %{
      id: o.id,
      attempt_number: o.attempt_number,
      proposer_seat_id: o.proposer_seat_id,
      proposer_name: seat_name(o.proposer, "Player"),
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

  defp correction_view(c) do
    %{
      id: c.id,
      page_id: c.page_id,
      seat_id: c.seat_id,
      author_name: seat_name(c.seat, "Player"),
      attempt_number: c.attempt_number,
      target: c.target,
      original_value: c.original_value,
      corrected_value: c.corrected_value,
      note: c.note,
      inserted_at: c.inserted_at
    }
  end

  # The name a row's Seat goes by, or what the book calls a Seat it cannot name.
  defp seat_name(seat, unnamed), do: (seat && seat.name) || unnamed
end
