defmodule MeaningGame.Chronicle.Markdown do
  @moduledoc """
  Renders and parses the Chronicle as Markdown on demand (ADR-0003, ticket 08).

  Both Jacob and coding agents can read and round-trip past Pages
  without a database client.
  """

  alias MeaningGame.Chronicle
  alias MeaningGame.Repo
  alias MeaningGame.Rooms.Room

  @doc """
  Renders the Chronicle for a Room as a Markdown document.
  """
  @spec render(Ecto.UUID.t() | String.t()) :: String.t()
  def render(room_id_or_slug) do
    room = resolve_room(room_id_or_slug)
    page_views = Chronicle.page_views(room.id, :asc)

    header = "# The Chronicle\n\n## Room: #{room.slug}\n\n"

    spend = Chronicle.spend(room.id)
    spend_line = Chronicle.spend_line(spend)

    if page_views == [] do
      header <> "No pages played yet.\n\n---\n\n" <> spend_line <> "\n"
    else
      pages_md =
        page_views
        |> Enum.with_index(1)
        |> Enum.map(fn {page, index} -> render_page(page, index) end)
        |> Enum.join("\n\n---\n\n")

      header <> pages_md <> "\n\n---\n\n" <> spend_line <> "\n"
    end
  end

  defp render_page(page, index) do
    bookends_str = Enum.join(page.bookends, " · ")
    outcome_str = if page.melded, do: "Melded", else: "Unmelded"
    closed_detail = "#{outcome_str} (#{page.closed_because})"
    closeness_str = if page.closeness, do: "#{page.closeness} / 100", else: "None"

    give_lines =
      cond do
        page[:gives] && page[:gives] != [] ->
          Enum.map(page.gives, fn g -> "- Give (#{g.seat_name}): #{g.text}" end)

        page[:give] ->
          ["- Give: #{page.give}"]

        true ->
          []
      end

    experiment_lines =
      cond do
        page[:experiment_unblinded] && page[:arm] ->
          ["- Experiment: Bait against plain", "- Arm: #{page.arm}"]

        page[:experiment_id] ->
          ["- Experiment: Blinded (#{page.experiment_id})"]

        true ->
          []
      end

    meta_lines =
      [
        "### Page #{index}: #{bookends_str}",
        "- Bookends: #{bookends_str}",
        "- Outcome: #{closed_detail}",
        "- Closeness: #{closeness_str}"
      ] ++
        give_lines ++
        experiment_lines ++
        [
          "- Opened: #{page.opened_at && DateTime.to_iso8601(page.opened_at)}",
          "- Closed: #{page.closed_at && DateTime.to_iso8601(page.closed_at)}"
        ]

    attempts_md =
      page.attempts
      |> Enum.map(&render_attempt/1)
      |> Enum.join("\n\n")

    page_level_corrections =
      Enum.filter(page.corrections, fn c -> is_nil(c.attempt_number) end)

    page_corrections_md =
      case page_level_corrections do
        [] ->
          nil

        corrections ->
          corr_items =
            Enum.map(corrections, fn c ->
              orig = if c.original_value, do: " from \"#{c.original_value}\"", else: ""
              note = if c.note, do: " (Note: \"#{c.note}\")", else: ""

              "  - By #{c.author_name}: corrected #{c.target}#{orig} to \"#{c.corrected_value}\"#{note}"
            end)
            |> Enum.join("\n")

          "##### Corrections\n" <> corr_items
      end

    sections =
      [Enum.join(meta_lines, "\n"), render_recap(page[:recap]), attempts_md, page_corrections_md]
      |> Enum.reject(&(&1 in [nil, ""]))

    Enum.join(sections, "\n\n")
  end

  # The Scribe's paragraph, as a blockquote at the head of the Page — which is
  # where a reader wants the story before the ledger of what was written, and
  # which is one Markdown construct rather than a heading the parser would have
  # to tell from an attempt's.
  defp render_recap(nil), do: nil

  defp render_recap(recap) do
    [recap.recap, recap[:callback]]
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
    bookends_str = Enum.join(attempt.bookends, " · ")

    bridges_lines =
      attempt.bridges
      |> Enum.map(fn b -> "  - #{b.seat_name}: #{b.bridge}" end)
      |> Enum.join("\n")

    verdict_lines =
      case attempt.verdicts do
        [] ->
          ["- Closeness: Ungraded"]

        [single] ->
          band_str = if single.band, do: " (#{single.band})", else: ""
          lines = ["- Closeness: #{single.closeness} / 100#{band_str}"]

          lines =
            if single.reasoning, do: lines ++ ["- Reasoning: #{single.reasoning}"], else: lines

          lines = if single.quip, do: lines ++ ["- Quip: #{single.quip}"], else: lines

          if single.model do
            cost_str = if single.cost_usd, do: "$#{single.cost_usd}", else: "$0.0"

            lines ++
              [
                "- Model: #{single.model} (prompt #{single.prompt_version}, #{single.latency_ms || 0}ms, #{cost_str})"
              ]
          else
            lines
          end

        # An attempt written before ADR-0010, when the Assayer answered one pair
        # at a time. The book is append-only, so those rows still read as pairs.
        multiple ->
          Enum.flat_map(multiple, fn v ->
            band_str = if v.band, do: " (#{v.band})", else: ""
            bridges_label = Enum.join(v.bridges, " / ")
            lines = ["- Pair [#{bridges_label}]: #{v.closeness} / 100#{band_str}"]
            lines = if v.reasoning, do: lines ++ ["  Reasoning: #{v.reasoning}"], else: lines
            lines = if v.quip, do: lines ++ ["  Quip: #{v.quip}"], else: lines
            lines
          end)
      end

    overrules_md =
      case attempt.overrules do
        [] ->
          nil

        overrules ->
          overrules_lines =
            Enum.map(overrules, fn o ->
              """
              ##### Overrule
              - Proposed by: #{o.proposer_name}
              - Original: #{o.machine_closeness} / 100 ("#{o.machine_reasoning}")
              - Overruled: #{o.couple_closeness} / 100 ("#{o.couple_reasoning}")
              """
              |> String.trim_trailing()
            end)
            |> Enum.join("\n\n")

          overrules_lines
      end

    corrections_md =
      case attempt.corrections do
        [] ->
          nil

        corrections ->
          corr_items =
            Enum.map(corrections, fn c ->
              orig = if c.original_value, do: " from \"#{c.original_value}\"", else: ""
              note = if c.note, do: " (Note: \"#{c.note}\")", else: ""

              "  - By #{c.author_name}: corrected #{c.target}#{orig} to \"#{c.corrected_value}\"#{note}"
            end)
            |> Enum.join("\n")

          "##### Corrections\n" <> corr_items
      end

    fairness_md =
      case Map.get(attempt, :fairness_taps, []) do
        [] ->
          nil

        taps ->
          items =
            Enum.map(taps, fn t ->
              display_label = MeaningGame.Chronicle.FairnessTap.label_human(t.label)
              "#{t.seat_name}: #{display_label}"
            end)
            |> Enum.join(", ")

          "- Fairness: #{items}"
      end

    attempt_lines =
      ([
         "#### Attempt #{attempt.number}",
         "- Bookends: #{bookends_str}",
         "- Bridges:\n#{bridges_lines}"
       ] ++
         verdict_lines ++
         [fairness_md, overrules_md, corrections_md])
      |> Enum.reject(&is_nil/1)

    Enum.join(attempt_lines, "\n")
  end

  @doc """
  Parses an exported Chronicle Markdown string back into structured data.
  """
  @spec parse(String.t()) :: {:ok, [map()]} | {:error, term()}
  def parse(markdown) do
    # Strip any trailing spend footer section
    markdown =
      case String.split(markdown, ~r/\n---\n\nSpend:/, parts: 2) do
        [clean, _spend] -> clean
        [clean] -> clean
      end

    # Split by Page sections
    page_chunks =
      Regex.split(~r/(?=### Page \d+:)/, markdown)
      |> Enum.filter(&String.starts_with?(String.trim_leading(&1), "### Page "))

    parsed_pages = Enum.map(page_chunks, &parse_page_chunk/1)
    {:ok, parsed_pages}
  end

  defp parse_page_chunk(chunk) do
    [header_part | attempt_parts] = Regex.split(~r/(?=#### Attempt \d+)/, chunk)

    # Parse Page header
    [page_title | meta_lines] = String.split(header_part, "\n", trim: true)
    [_, bookends_text] = Regex.run(~r/### Page \d+:\s*(.*)/, page_title)
    bookends = String.split(bookends_text, " · ") |> Enum.map(&String.trim/1)

    outcome_line =
      Enum.find(
        meta_lines,
        &(String.starts_with?(&1, "- Outcome:") or String.starts_with?(&1, "- Status:"))
      )

    melded = outcome_line != nil and String.contains?(outcome_line, "Melded")

    closeness_line = Enum.find(meta_lines, &String.starts_with?(&1, "- Closeness:"))
    closeness = parse_closeness(closeness_line)

    give_lines =
      Enum.filter(
        meta_lines,
        &(String.starts_with?(&1, "- Give:") or Regex.match?(~r/^- Give \([^)]+\):/, &1))
      )

    gives =
      Enum.map(give_lines, fn line ->
        case Regex.run(~r/^- Give \(([^)]+)\):\s*(.*)/, line) do
          [_, name, text] ->
            %{seat_name: name, text: text}

          nil ->
            text = line |> String.replace_prefix("- Give:", "") |> String.trim()
            %{seat_name: "Seat", text: text}
        end
      end)

    give =
      case gives do
        [single] -> single.text
        [first | _] -> first.text
        [] -> nil
      end

    experiment_line = Enum.find(meta_lines, &String.starts_with?(&1, "- Experiment:"))

    experiment =
      if experiment_line do
        experiment_line
        |> String.replace_prefix("- Experiment:", "")
        |> String.trim()
      end

    arm_line = Enum.find(meta_lines, &String.starts_with?(&1, "- Arm:"))

    arm =
      if arm_line do
        arm_line
        |> String.replace_prefix("- Arm:", "")
        |> String.trim()
      end

    attempts = Enum.map(attempt_parts, &parse_attempt_chunk/1)

    %{
      bookends: bookends,
      melded: melded,
      closeness: closeness,
      give: give,
      gives: gives,
      experiment: experiment,
      arm: arm,
      recap: parse_recap(meta_lines),
      attempts: attempts
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

  defp parse_attempt_chunk(chunk) do
    lines = String.split(chunk, "\n")
    [title | _] = lines
    [_, num_str] = Regex.run(~r/#### Attempt (\d+)/, title)
    number = String.to_integer(num_str)

    bookends_line =
      Enum.find(
        lines,
        &(String.starts_with?(String.trim(&1), "- Bookends:") or
            String.starts_with?(String.trim(&1), "- Anchors:"))
      )

    bookends =
      if bookends_line do
        bookends_line
        |> String.trim()
        |> String.replace_prefix("- Bookends:", "")
        # Compatibility clause: accept old Anchors: lines so earlier exports round-trip
        |> String.replace_prefix("- Anchors:", "")
        |> String.trim()
        |> String.split(" · ")
        |> Enum.map(&String.trim/1)
      else
        []
      end

    bridges =
      lines
      |> Enum.flat_map(fn line ->
        case Regex.run(~r/^\s*-\s*([^:]+):\s*(.*)$/, line) do
          [_, name, bridge]
          when name not in [
                 "Bookends",
                 "Anchors",
                 "Bridges",
                 "Closeness",
                 "Reasoning",
                 "Quip",
                 "Model",
                 "Outcome",
                 "Status",
                 "Opened",
                 "Closed",
                 "Proposed by",
                 "Original",
                 "Overruled",
                 "Fairness"
               ] ->
            if String.starts_with?(name, "By ") do
              []
            else
              [{String.trim(name), String.trim(bridge)}]
            end

          _ ->
            []
        end
      end)

    closeness_line = Enum.find(lines, &String.starts_with?(String.trim(&1), "- Closeness:"))
    closeness = parse_closeness(closeness_line)
    band = parse_band(closeness_line)

    reasoning =
      case Enum.find(lines, &String.starts_with?(String.trim(&1), "- Reasoning:")) do
        nil -> nil
        line -> line |> String.replace_prefix("- Reasoning:", "") |> String.trim()
      end

    quip =
      case Enum.find(lines, &String.starts_with?(String.trim(&1), "- Quip:")) do
        nil -> nil
        line -> line |> String.replace_prefix("- Quip:", "") |> String.trim()
      end

    fairness_line = Enum.find(lines, &String.starts_with?(String.trim(&1), "- Fairness:"))
    fairness_taps = parse_fairness_line(fairness_line)
    overrule = parse_overrule_section(chunk)
    corrections = parse_corrections_section(chunk)

    %{
      number: number,
      bookends: bookends,
      bridges: bridges,
      closeness: closeness,
      band: band,
      reasoning: reasoning,
      quip: quip,
      fairness_taps: fairness_taps,
      overrule: overrule,
      corrections: corrections
    }
  end

  defp parse_overrule_section(chunk) do
    if String.contains?(chunk, "##### Overrule") do
      [_, overrule_part] = String.split(chunk, "##### Overrule", parts: 2)
      lines = String.split(overrule_part, "\n")

      proposer =
        case Enum.find(lines, &String.contains?(&1, "- Proposed by:")) do
          nil -> "Player"
          l -> l |> String.replace(~r/.*- Proposed by:\s*/, "") |> String.trim()
        end

      orig_closeness =
        case Enum.find(lines, &String.contains?(&1, "- Original:")) do
          nil -> nil
          l -> parse_closeness(l)
        end

      overruled_closeness =
        case Enum.find(lines, &String.contains?(&1, "- Overruled:")) do
          nil -> nil
          l -> parse_closeness(l)
        end

      reasoning =
        case Enum.find(lines, &String.contains?(&1, "- Overruled:")) do
          nil ->
            ""

          l ->
            case Regex.run(~r/\("([^"]+)"\)/, l) do
              [_, r] -> r
              _ -> ""
            end
        end

      %{
        proposer: proposer,
        original: orig_closeness,
        overruled: overruled_closeness,
        reasoning: reasoning
      }
    else
      nil
    end
  end

  defp parse_corrections_section(chunk) do
    if String.contains?(chunk, "##### Corrections") do
      [_, corr_part] = String.split(chunk, "##### Corrections", parts: 2)

      corr_part
      |> String.split("\n")
      |> Enum.flat_map(fn line ->
        case Regex.run(
               ~r/^\s*-\s*By\s+([^:]+):\s*corrected\s+(\w+)(?:\s+from\s+"([^"]+)")?\s+to\s+"([^"]+)"(?:\s+\(Note:\s*"([^"]+)"\))?/,
               line
             ) do
          [_, author, target, orig, corrected, note] ->
            [
              %{
                author: String.trim(author),
                target: target,
                original: orig,
                corrected: corrected,
                note: note
              }
            ]

          [_, author, target, orig, corrected] ->
            [
              %{
                author: String.trim(author),
                target: target,
                original: orig,
                corrected: corrected,
                note: nil
              }
            ]

          _ ->
            []
        end
      end)
    else
      []
    end
  end

  defp parse_fairness_line(nil), do: []

  defp parse_fairness_line(line) do
    line
    |> String.replace_prefix("- Fairness:", "")
    |> String.trim()
    |> String.split(",")
    |> Enum.flat_map(fn part ->
      case String.split(part, ":", parts: 2) do
        [name, label] ->
          label_norm =
            case String.trim(label) do
              "too kind" -> "too_kind"
              "too harsh" -> "too_harsh"
              other -> other
            end

          [%{seat_name: String.trim(name), label: label_norm}]

        _ ->
          []
      end
    end)
  end

  defp parse_closeness(nil), do: nil

  defp parse_closeness(line) do
    case Regex.run(~r/(\d+)\s*\/\s*100/, line) do
      [_, digits] -> String.to_integer(digits)
      _ -> nil
    end
  end

  defp parse_band(nil), do: nil

  defp parse_band(line) do
    case Regex.run(~r/\(([^)]+)\)/, line) do
      [_, band] -> band
      _ -> nil
    end
  end

  defp resolve_room(room_id_or_slug) do
    if is_binary(room_id_or_slug) and
         Regex.match?(
           ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i,
           room_id_or_slug
         ) do
      Repo.get!(Room, room_id_or_slug)
    else
      Repo.get_by!(Room, slug: room_id_or_slug)
    end
  end
end
