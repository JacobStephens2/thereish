defmodule Thereish.Chronicle.Markdown do
  @moduledoc """
  The Chronicle's Markdown export, in both directions (ADR-0003, ticket 08).

  Both Jacob and coding agents can read and round-trip past Pages
  without a database client.

  Pure. `render/3` takes the Room's Code, its Page views oldest first and its
  Spend tally, and answers the document; `parse/1` reads a document back. This
  is not a seam over Postgres: the Chronicle keeps the reads, and this module
  owns only the format, so every rule about it can be tested from in-memory
  Page views.

  Render and parse share one vocabulary of line labels, and parse reads by
  structure rather than by guessing what a line is. Seat names are typed freely,
  so a Bridge is whatever sits indented under its Attempt's `- Bridges:` line,
  whatever its Seat is called.
  """

  alias Thereish.Chronicle.Opinion
  alias Thereish.Chronicle.PageView
  alias Thereish.Chronicle.Spend
  alias Thereish.Experiments
  alias Thereish.Mask

  @typedoc """
  One correction read back, from a Page or from one of its Attempts. Its
  `original` is empty when none was written.
  """
  @type parsed_correction :: %{
          author: String.t(),
          target: String.t(),
          original: String.t(),
          corrected: String.t(),
          note: String.t() | nil
        }

  @typedoc "One overrule read back: the first one written about its Attempt."
  @type parsed_overrule :: %{
          proposer: String.t(),
          original: integer() | nil,
          overruled: integer() | nil,
          reasoning: String.t()
        }

  @typedoc """
  One Attempt read back. An Attempt written before ADR-0010, graded one pair at
  a time, reads with no closeness, band, reasoning or quip.
  """
  @type parsed_attempt :: %{
          number: integer(),
          bookends: [String.t()],
          bridges: [{seat_name :: String.t(), bridge :: String.t()}],
          closeness: integer() | nil,
          band: String.t() | nil,
          reasoning: String.t() | nil,
          quip: String.t() | nil,
          carried: [String.t()] | nil,
          fairness_taps: [%{seat_name: String.t(), label: String.t()}],
          overrule: parsed_overrule() | nil,
          corrections: [parsed_correction()]
        }

  @typedoc """
  One Page read back. A Give written before Give rows reads as from "Seat".
  `corrections` are the Page-level ones; an Attempt's own are on the Attempt.
  """
  @type parsed_page :: %{
          bookends: [String.t()],
          melded: boolean(),
          closeness: integer() | nil,
          give: String.t() | nil,
          gives: [%{seat_name: String.t(), text: String.t()}],
          experiment: String.t() | nil,
          arm: String.t() | nil,
          track: String.t() | nil,
          vamp: String.t() | nil,
          recap: %{recap: String.t(), callback: String.t() | nil} | nil,
          attempts: [parsed_attempt()],
          corrections: [parsed_correction()]
        }

  # Every line label the export writes, each with the older spellings parse
  # still accepts so that earlier exports, such as `priv/chronicles/dust.md`,
  # keep reading. Render writes only `- <label>:`; aliases are read-only.
  @labels %{
    bookends: {"Bookends", ["- Anchors:"]},
    outcome: {"Outcome", ["- Status:"]},
    closeness: {"Closeness", []},
    rule: {"Rule", []},
    bookend: {"Bookend", []},
    give: {"Give", []},
    track: {"Track", ["Track:"]},
    vamp: {"Vamp", ["Vamp:"]},
    mask: {"Mask", []},
    experiment: {"Experiment", []},
    arm: {"Arm", []},
    opened: {"Opened", []},
    closed: {"Closed", []},
    bridges: {"Bridges", []},
    reasoning: {"Reasoning", []},
    quip: {"Quip", []},
    carried: {"Carried", []},
    model: {"Model", []},
    fairness: {"Fairness", []},
    pair: {"Pair", []},
    proposed_by: {"Proposed by", []},
    original: {"Original", []},
    overruled: {"Overruled", []}
  }

  @page_heading "### Page"
  @attempt_heading "#### Attempt"
  @page_corrections_heading "#### Corrections"
  @overrule_heading "##### Overrule"
  @attempt_corrections_heading "##### Corrections"
  @item_indent "  - "
  @pair_indent "  "

  @correction_pattern ~r/^\s*-\s*By\s+([^:]+):\s*corrected\s+(\w+)(?:\s+from\s+"([^"]+)")?\s+to\s+"([^"]+)"(?:\s+\(Note:\s*"([^"]+)"\))?/

  @doc """
  Renders a Room's Chronicle as a Markdown document, from its Code, its Page
  views oldest first and its Spend tally.
  """
  @spec render(String.t(), [PageView.t()], Spend.tally()) :: String.t()
  def render(code, page_views, spend) do
    header = "# The Chronicle\n\n## Room: #{code}\n\n"
    footer = "\n\n---\n\n" <> Spend.line(spend) <> "\n"

    case page_views do
      [] ->
        header <> "No pages played yet." <> footer

      pages ->
        pages_md =
          pages
          |> Enum.with_index(1)
          |> Enum.map_join("\n\n---\n\n", fn {page, index} -> render_page(page, index) end)

        header <> pages_md <> footer
    end
  end

  defp render_page(page, index) do
    bookends_str = Enum.join(page.bookends, " · ")
    outcome_str = if page.melded, do: "Melded", else: "Unmelded"
    closeness_str = if page.closeness, do: "#{page.closeness} / 100", else: "None"

    give_lines =
      Enum.map(page.gives, fn
        %{seat_name: nil} = g -> line(:give, g.text)
        g -> line(:give, g.seat_name, g.text)
      end)

    experiment_lines =
      cond do
        page.experiment_unblinded && page.arm ->
          [
            line(:experiment, Experiments.definition(page.experiment_id).name),
            line(:arm, page.arm)
          ]

        page.experiment_id ->
          [line(:experiment, "Blinded (#{page.experiment_id})")]

        true ->
          []
      end

    track_lines = if page.track, do: [line(:track, page.track.title)], else: []
    vamp_lines = if page.vamp, do: [line(:vamp, "the short piece")], else: []

    mask_lines =
      for(g <- page.gives, url = Mask.url(g.mask), do: line(:mask, g.seat_name, url)) ++
        for m <- page.masks_without_give,
            do: line(:mask, m.seat_name || m.seat_id, Mask.url(m.mask))

    rule_lines =
      case page.full_table do
        true -> [line(:rule, "Full table")]
        false -> [line(:rule, "Two Bookends")]
        _ -> []
      end

    bookend_give_lines =
      for origin <- page.bookend_origins, origin.give && origin.word do
        line(:bookend, origin.word, "from #{origin.seat_name || "Seat"}'s #{origin.give}")
      end

    meta_lines =
      [
        "#{@page_heading} #{index}: #{bookends_str}",
        line(:bookends, bookends_str),
        line(:outcome, "#{outcome_str} (#{page.closed_because})"),
        line(:closeness, closeness_str)
      ] ++
        rule_lines ++
        bookend_give_lines ++
        give_lines ++
        track_lines ++
        vamp_lines ++
        mask_lines ++
        experiment_lines ++
        [
          line(:opened, page.opened_at && DateTime.to_iso8601(page.opened_at)),
          line(:closed, page.closed_at && DateTime.to_iso8601(page.closed_at))
        ]

    attempts_md = Enum.map_join(page.attempts, "\n\n", &render_attempt/1)

    # A sibling of the Attempts rather than a sub-section of the last one, so
    # that parse can tell where the last Attempt ends.
    page_corrections_md =
      page.corrections
      |> Enum.filter(&is_nil(&1.attempt_number))
      |> render_corrections(@page_corrections_heading)

    [Enum.join(meta_lines, "\n"), render_recap(page.recap), attempts_md, page_corrections_md]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  # The Scribe's paragraph, as a blockquote at the head of the Page — which is
  # where a reader wants the story before the ledger of what was written, and
  # which is one Markdown construct rather than a heading the parser would have
  # to tell from an attempt's.
  defp render_recap(nil), do: nil

  defp render_recap(recap) do
    [recap.recap, recap.callback]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join("\n>\n", &quote_paragraph/1)
  end

  # Every line of a paragraph gets its own `> `, because a blockquote whose
  # second line is not marked is not a blockquote to anything that reads
  # Markdown, this parser included.
  defp quote_paragraph(paragraph) do
    paragraph |> String.split("\n") |> Enum.map_join("\n", &("> " <> &1))
  end

  defp render_attempt(attempt) do
    bridge_lines = Enum.map(attempt.bridges, &"#{@item_indent}#{&1.seat_name}: #{&1.bridge}")

    verdict_lines =
      case attempt.verdicts do
        [] ->
          [line(:closeness, "Ungraded")]

        [single] ->
          [line(:closeness, "#{single.closeness} / 100#{band(single)}")] ++
            if(single.reasoning, do: [line(:reasoning, single.reasoning)], else: []) ++
            if(single.quip, do: [line(:quip, single.quip)], else: []) ++
            if(attempt.carried not in [nil, []],
              do: [line(:carried, Thereish.Game.join_and(attempt.carried))],
              else: []
            ) ++
            if(single.model, do: [model_line(single)], else: [])

        # An attempt written before ADR-0010, when the Assayer answered one pair
        # at a time. The book is append-only, so those rows still read as pairs.
        multiple ->
          Enum.flat_map(multiple, &pair_lines/1)
      end

    fairness_lines =
      case attempt.fairness_taps do
        [] ->
          []

        taps ->
          [
            line(
              :fairness,
              Enum.map_join(taps, ", ", &"#{&1.reviewer_name}: #{Opinion.human(&1.label)}")
            )
          ]
      end

    overrules_md =
      case attempt.overrules do
        [] -> nil
        overrules -> Enum.map_join(overrules, "\n\n", &render_overrule/1)
      end

    ([
       "#{@attempt_heading} #{attempt.number}",
       line(:bookends, Enum.join(attempt.bookends, " · ")),
       Enum.join([prefix(:bridges) | bridge_lines], "\n")
     ] ++
       verdict_lines ++
       fairness_lines ++
       [overrules_md, render_corrections(attempt.corrections, @attempt_corrections_heading)])
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp band(%{band: nil}), do: ""
  defp band(%{band: band}), do: " (#{band})"

  defp model_line(verdict) do
    cost_str = if verdict.cost_usd, do: "$#{verdict.cost_usd}", else: "$0.0"

    line(
      :model,
      "#{verdict.model} (prompt #{verdict.prompt_version}, #{verdict.latency_ms || 0}ms, #{cost_str})"
    )
  end

  # A pair Verdict's Reasoning and Quip sit indented under it, unbulleted, so
  # that parse never reads them as the Attempt's own or as a Bridge.
  defp pair_lines(verdict) do
    pair = "- #{label(:pair)} [#{Enum.join(verdict.bridges, " / ")}]"

    ["#{pair}: #{verdict.closeness} / 100#{band(verdict)}"] ++
      if(verdict.reasoning,
        do: ["#{@pair_indent}#{label(:reasoning)}: #{verdict.reasoning}"],
        else: []
      ) ++
      if verdict.quip, do: ["#{@pair_indent}#{label(:quip)}: #{verdict.quip}"], else: []
  end

  defp render_overrule(o) do
    Enum.join(
      [
        @overrule_heading,
        line(:proposed_by, o.proposer_name),
        line(:original, "#{o.machine_closeness} / 100 (\"#{o.machine_reasoning}\")"),
        line(:overruled, "#{o.couple_closeness} / 100 (\"#{o.couple_reasoning}\")")
      ],
      "\n"
    )
  end

  defp render_corrections([], _heading), do: nil

  defp render_corrections(corrections, heading) do
    Enum.join([heading | Enum.map(corrections, &correction_line/1)], "\n")
  end

  defp correction_line(c) do
    orig = if c.original_value, do: " from \"#{c.original_value}\"", else: ""
    note = if c.note, do: " (Note: \"#{c.note}\")", else: ""

    "#{@item_indent}By #{c.author_name}: corrected #{c.target}#{orig} to \"#{c.corrected_value}\"#{note}"
  end

  defp label(key), do: @labels |> Map.fetch!(key) |> elem(0)

  defp prefix(key), do: "- #{label(key)}:"

  defp line(key, value), do: "#{prefix(key)} #{value}"

  defp line(key, qualifier, value), do: "- #{label(key)} (#{qualifier}): #{value}"

  @doc """
  Parses an exported Chronicle Markdown string back into structured data.
  """
  @spec parse(String.t()) :: {:ok, [parsed_page()]} | {:error, term()}
  def parse(markdown) do
    # Strip any trailing spend footer section
    markdown =
      case String.split(markdown, ~r/\n---\n\nSpend:/, parts: 2) do
        [clean, _spend] -> clean
        [clean] -> clean
      end

    {_preamble, pages} =
      markdown
      |> String.split("\n")
      |> sections(&Regex.match?(~r/^#{@page_heading} \d+:/, &1))

    {:ok, Enum.map(pages, &parse_page/1)}
  end

  defp parse_page({heading, body}) do
    [_, bookends_text] = Regex.run(~r/^#{@page_heading} \d+:\s*(.*)/, heading)
    bookends = split_bookends(bookends_text)

    {meta_lines, page_sections} = sections(body, &String.starts_with?(&1, "#### "))

    gives =
      Enum.flat_map(meta_lines, fn line ->
        case qualified(line, :give) do
          {nil, text} -> [%{seat_name: "Seat", text: text}]
          {name, text} -> [%{seat_name: name, text: text}]
          nil -> []
        end
      end)

    give =
      case gives do
        [first | _] -> first.text
        [] -> nil
      end

    attempts =
      for {heading, body} <- page_sections,
          [_, number] <- [Regex.run(~r/^#{@attempt_heading} (\d+)/, heading)] do
        parse_attempt(String.to_integer(number), body)
      end

    corrections = parse_corrections(page_sections, @page_corrections_heading)

    %{
      bookends: bookends,
      melded: (field(meta_lines, :outcome) || "") =~ "Melded",
      closeness: parse_closeness(field(meta_lines, :closeness)),
      give: give,
      gives: gives,
      experiment: field(meta_lines, :experiment),
      arm: field(meta_lines, :arm),
      track: blank_to_nil(field(meta_lines, :track)),
      vamp: blank_to_nil(field(meta_lines, :vamp)),
      recap: parse_recap(meta_lines),
      attempts: attempts,
      corrections: corrections
    }
  end

  # The blockquote, back into its two paragraphs. A Page the Scribe never got to
  # has none, which reads back as `nil` rather than as an empty paragraph.
  #
  # Paragraphs are separated by the bare `>` the renderer writes between them,
  # and a paragraph that wrapped over several lines is joined back up — the gate
  # keeps a recap to eighty words, but nothing keeps those eighty words on one
  # line, and a round trip that quietly dropped the second line would be a
  # Chronicle that edits itself.
  defp parse_recap(meta_lines) do
    case meta_lines |> Enum.filter(&String.starts_with?(&1, ">")) |> paragraphs() do
      [] -> nil
      [recap] -> %{recap: recap, callback: nil}
      [recap, callback | _] -> %{recap: recap, callback: callback}
    end
  end

  defp paragraphs(lines) do
    lines
    |> Enum.map(&(&1 |> String.replace_prefix(">", "") |> String.trim()))
    |> Enum.chunk_by(&(&1 == ""))
    |> Enum.reject(&(&1 == [""]))
    |> Enum.map(&Enum.join(&1, "\n"))
    |> Enum.reject(&(&1 == ""))
  end

  # An Attempt's own fields are read only from its top-level lines, never from
  # a Bridge under it or a pair Verdict's indented lines.
  defp parse_attempt(number, body) do
    {lines, attempt_sections} = sections(body, &String.starts_with?(&1, "##### "))
    closeness_value = field(lines, :closeness)

    overrule =
      Enum.find_value(attempt_sections, fn
        {@overrule_heading <> _, overrule_lines} -> parse_overrule(overrule_lines)
        _ -> nil
      end)

    corrections = parse_corrections(attempt_sections, @attempt_corrections_heading)

    %{
      number: number,
      bookends: lines |> field(:bookends) |> split_bookends(),
      bridges: parse_bridges(lines),
      closeness: parse_closeness(closeness_value),
      band: parse_band(closeness_value),
      reasoning: field(lines, :reasoning),
      quip: field(lines, :quip),
      carried: lines |> field(:carried) |> parse_joined_words(),
      fairness_taps: lines |> field(:fairness) |> parse_fairness(),
      overrule: overrule,
      corrections: corrections
    }
  end

  # Exactly the indented lines directly under `- Bridges:`. Each splits at its
  # last ": ", since Legality never lets a Bridge hold a colon while a Seat name
  # may.
  defp parse_bridges(lines) do
    lines
    |> Enum.drop_while(&(String.trim_trailing(&1) != prefix(:bridges)))
    |> Enum.drop(1)
    |> Enum.take_while(&String.starts_with?(&1, @item_indent))
    |> Enum.flat_map(fn line ->
      case line |> String.replace_prefix(@item_indent, "") |> String.split(": ") do
        [_no_separator] ->
          []

        parts ->
          {name, [bridge]} = Enum.split(parts, -1)
          [{name |> Enum.join(": ") |> String.trim(), String.trim(bridge)}]
      end
    end)
  end

  defp parse_overrule(lines) do
    overruled = field(lines, :overruled)

    reasoning =
      case overruled && Regex.run(~r/\("([^"]+)"\)/, overruled) do
        [_, r] -> r
        _ -> ""
      end

    %{
      proposer: field(lines, :proposed_by) || "Player",
      original: parse_closeness(field(lines, :original)),
      overruled: parse_closeness(overruled),
      reasoning: reasoning
    }
  end

  # Every correction written under the heading, in the sections given.
  defp parse_corrections(sections, heading) do
    for {^heading, lines} <- sections, line <- lines, correction <- parse_correction(line) do
      correction
    end
  end

  defp parse_correction(line) do
    case Regex.run(@correction_pattern, line) do
      [_, author, target, orig, corrected | note] ->
        [
          %{
            author: String.trim(author),
            target: target,
            original: orig,
            corrected: corrected,
            note: List.first(note)
          }
        ]

      _ ->
        []
    end
  end

  defp parse_fairness(nil), do: []

  # Each tap splits at its last ":", since an Opinion's label never holds one
  # while a Seat name may.
  defp parse_fairness(value) do
    value
    |> String.split(",")
    |> Enum.flat_map(fn part ->
      case String.split(part, ":") do
        [_no_separator] ->
          []

        parts ->
          {name, [label]} = Enum.split(parts, -1)

          label_norm =
            case Opinion.label(label) do
              {:ok, parsed} -> parsed
              {:error, :invalid_label} -> String.trim(label)
            end

          [%{seat_name: name |> Enum.join(":") |> String.trim(), label: label_norm}]
      end
    end)
  end

  # Splits lines at each heading the predicate picks: the lines before the first
  # heading, then each heading with the lines under it.
  defp sections(lines, heading?) do
    {head, rest} = Enum.split_while(lines, &(not heading?.(&1)))
    {head, headed(rest, heading?)}
  end

  defp headed([], _heading?), do: []

  defp headed([heading | rest], heading?) do
    {body, rest} = Enum.split_while(rest, &(not heading?.(&1)))
    [{heading, body} | headed(rest, heading?)]
  end

  # The value of the first line written under the label or one of its aliases.
  defp field(lines, key) do
    {_label, aliases} = Map.fetch!(@labels, key)
    prefixes = [prefix(key) | aliases]

    Enum.find_value(lines, fn line ->
      Enum.find_value(prefixes, fn p ->
        if String.starts_with?(line, p), do: line |> String.replace_prefix(p, "") |> String.trim()
      end)
    end)
  end

  # A label written with or without a qualifier, as in `- Give (Mara): text`
  # or `- Give: text`: answers the qualifier, or nil, and the value. The
  # qualifier runs to the first "): ", so a Seat name may hold a parenthesis.
  defp qualified(line, key) do
    case Regex.run(~r/^- #{Regex.escape(label(key))} \((.+?)\):\s*(.*)/, line) do
      [_, qualifier, value] ->
        {qualifier, value}

      nil ->
        if String.starts_with?(line, prefix(key)),
          do: {nil, line |> String.replace_prefix(prefix(key), "") |> String.trim()}
    end
  end

  defp split_bookends(nil), do: []
  defp split_bookends(text), do: text |> String.split(" · ") |> Enum.map(&String.trim/1)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp parse_closeness(nil), do: nil

  defp parse_closeness(value) do
    case Regex.run(~r/(\d+)\s*\/\s*100/, value) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp parse_band(nil), do: nil

  defp parse_band(value) do
    case Regex.run(~r/\(([^)]+)\)/, value) do
      [_, band] -> band
      _ -> nil
    end
  end

  defp parse_joined_words(nil), do: nil

  defp parse_joined_words(text) do
    text
    |> String.replace(" · ", ", ")
    |> String.replace(" and ", ", ")
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
