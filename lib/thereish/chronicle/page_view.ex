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

  alias Thereish.Chronicle.Attempt
  alias Thereish.Chronicle.Correction
  alias Thereish.Chronicle.FairnessTap
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

  @typedoc "One Give, under the Mask its Seat wore."
  @type give_view :: %{
          id: Ecto.UUID.t(),
          seat_id: Ecto.UUID.t() | nil,
          seat_name: String.t(),
          text: String.t(),
          order: integer(),
          mask: Mask.t() | nil
        }

  @typedoc """
  One Bookend as a chip. A first-Attempt chip from a Give names where its word
  came from; a later chip names the Seat whose Bridge it carried forward.
  """
  @type bookend_chip :: %{
          required(:word) => String.t(),
          required(:mask) => Mask.t() | nil,
          optional(:seat_id) => Ecto.UUID.t() | nil,
          optional(:give) => String.t() | nil,
          optional(:seat_name) => String.t() | nil
        }

  @typedoc "Where one opening Bookend came from, when a Give dealt it."
  @type bookend_origin :: %{
          word: String.t() | nil,
          give: String.t() | nil,
          seat_id: Ecto.UUID.t() | nil,
          seat_name: String.t() | nil
        }

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

  @typedoc "One Attempt, with the rows about it."
  @type attempt_view :: %{
          id: Ecto.UUID.t(),
          number: integer(),
          bookends: [String.t()],
          closeness: integer() | nil,
          melded: boolean(),
          bridges: [bridge_view()],
          verdicts: [verdict_view()],
          carried: [String.t()] | nil,
          bookend_chips: [bookend_chip()],
          overrules: [map()],
          corrections: [map()],
          fairness_taps: [map()]
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
          author_meta: map() | nil,
          music_meta: Track.t() | nil,
          vamp_meta: Vamp.t() | nil,
          masks: %{optional(Ecto.UUID.t()) => Mask.t()} | nil,
          give: String.t() | nil,
          theme: String.t() | nil,
          chapter: term(),
          bookends: [String.t()],
          bookend_origins: [bookend_origin()],
          full_table: boolean() | nil,
          closed_because: String.t(),
          melded: boolean(),
          closeness: integer() | nil,
          opened_at: DateTime.t(),
          closed_at: DateTime.t(),
          attempts: [attempt_view()],
          recap: recap_view() | nil,
          overrules: [map()],
          corrections: [map()],
          fairness_taps: [map()],
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
    :music_meta,
    :vamp_meta,
    :masks,
    :give,
    :theme,
    :chapter,
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
  plus every row about one of its Attempts (`about_attempt?/3`). Its
  corrections are the rows that name it.
  """
  @spec project(Page.t(), rows()) :: t()
  def project(%Page{} = page, rows) do
    of_page? = fn row ->
      row.page_id == page.id or Enum.any?(page.attempts, &about_attempt?(row, page, &1))
    end

    page_overrules = Enum.filter(rows.overrules, of_page?)
    page_corrections = Enum.filter(rows.corrections, &(&1.page_id == page.id))
    page_taps = Enum.filter(rows.fairness_taps, of_page?)

    attempts =
      page.attempts
      |> Enum.with_index()
      |> Enum.map(fn {attempt, index} ->
        attempt_view(page, attempt, index, page_overrules, page_corrections, page_taps)
      end)

    %__MODULE__{
      id: page.id,
      room_id: page.room_id,
      document: page.document,
      gives: Enum.map(page.gives, &give_view(&1, page.masks_meta || %{})),
      author_meta: page.author_meta,
      music_meta: page.music_meta,
      vamp_meta: page.vamp_meta,
      masks: page.masks_meta,
      give: page.document["give"] || page.document[:give],
      theme: page.document["theme"] || page.document[:theme],
      chapter: page.document["chapter"] || page.document[:chapter],
      bookends: opening_bookends(page),
      bookend_origins: bookend_origins(page.document),
      full_table: full_table(page.document),
      closed_because: page.closed_because,
      melded: page.melded,
      closeness: page.closeness,
      opened_at: page.opened_at,
      closed_at: page.closed_at,
      attempts: attempts,
      recap: latest_recap(rows.recaps, page, page_corrections),
      overrules: Enum.map(page_overrules, &format_overrule/1),
      corrections: Enum.map(page_corrections, &format_correction/1),
      fairness_taps: Enum.map(page_taps, &format_fairness_tap/1)
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

  defp attempt_view(page, attempt, index, page_overrules, page_corrections, page_taps) do
    attempt_overrules = Enum.filter(page_overrules, &about_attempt?(&1, page, attempt))
    attempt_corrections = Enum.filter(page_corrections, &(&1.attempt_number == attempt.number))
    attempt_taps = Enum.filter(page_taps, &about_attempt?(&1, page, attempt))

    bridges = Enum.map(attempt.bridges, &bridge_view(&1, attempt, page_corrections))
    verdicts = Enum.map(attempt.verdicts, &verdict_view(&1, attempt_overrules != []))

    %{
      id: attempt.id,
      number: attempt.number,
      bookends: attempt.bookends,
      closeness: attempt.closeness,
      melded: attempt.melded,
      bridges: bridges,
      verdicts: verdicts,
      carried: carried(page, index, attempt, verdicts, bridges),
      bookend_chips: bookend_chips(page, attempt, index),
      overrules: Enum.map(attempt_overrules, &format_overrule/1),
      corrections: Enum.map(attempt_corrections, &format_correction/1),
      fairness_taps: Enum.map(attempt_taps, &format_fairness_tap/1)
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
      seat_name: (b.seat && b.seat.name) || "Player",
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
      seat_name: (g.seat && g.seat.name) || "Seat",
      text: g.text,
      order: g.order,
      mask: Map.get(masks, g.seat_id)
    }
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
  # was one, else every Bridge at a Full table, else the furthest pair.
  defp carried(page, index, attempt, verdicts, bridges) do
    next = Enum.at(page.attempts, index + 1)

    cond do
      attempt.melded == true ->
        nil

      is_map(next) ->
        next.bookends

      full_table(page.document) == true ->
        Enum.map(bridges, & &1.bridge)

      true ->
        carried_pair(verdicts, bridges)
    end
  end

  defp carried_pair(verdicts, bridges) do
    case List.first(verdicts) do
      %{furthest: [_, _] = furthest} ->
        furthest

      %{graded: false} ->
        bridges |> Enum.map(& &1.bridge) |> Enum.take(2)

      _ ->
        nil
    end
  end

  defp full_table(doc) when is_map(doc) do
    case Map.get(doc, "full_table", Map.get(doc, :full_table)) do
      true -> true
      false -> false
      _ -> nil
    end
  end

  defp full_table(_), do: nil

  defp bookend_origins(doc) when is_map(doc) do
    raw =
      Map.get(doc, "bookend_origins") || Map.get(doc, :bookend_origins) ||
        Map.get(doc, "bookend_gives") || Map.get(doc, :bookend_gives) || []

    Enum.map(raw, fn origin ->
      %{
        word: origin[:word] || origin["word"],
        give: origin[:give] || origin["give"],
        seat_id: origin[:seat_id] || origin["seat_id"],
        seat_name: origin[:seat_name] || origin["seat_name"]
      }
    end)
  end

  defp bookend_origins(_), do: []

  # A first-Attempt chip names the Give its word came from and wears no Mask,
  # even when its origin names a Seat. A later chip claims the Bridge it carried
  # from the Attempt before, at most once per Bridge, and wears that Seat's Mask.
  defp bookend_chips(page, attempt, index) do
    origins = bookend_origins(page.document)
    masks = page.masks_meta || %{}

    cond do
      attempt.number == 1 and origins != [] ->
        Enum.map(origins, &Map.put(&1, :mask, nil))

      attempt.number == 1 ->
        Enum.map(attempt.bookends || [], &%{word: &1, mask: nil})

      true ->
        prev = Enum.at(page.attempts, index - 1)
        unclaimed = (prev && prev.bridges) || []

        {chips, _rest} =
          Enum.map_reduce(attempt.bookends || [], unclaimed, fn word, remaining ->
            case Enum.split_while(remaining, &(&1.bridge != word)) do
              {passed, [claimed | rest]} ->
                seat_id = claimed.seat_id
                mask = seat_id && Map.get(masks, seat_id)

                {%{word: word, seat_id: seat_id, mask: mask}, passed ++ rest}

              {_all, []} ->
                {%{word: word, mask: nil}, remaining}
            end
          end)

        chips
    end
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

  defp format_fairness_tap(t) do
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
  defp opinion_reviewer_name(t, _), do: (t.seat && t.seat.name) || "Player"

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
end
