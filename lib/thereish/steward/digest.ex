defmodule Thereish.Steward.Digest do
  @moduledoc """
  The Chronicle as a Steward role reads it before writing: every earlier Page in
  words, cut to what that role may know.

  Pure over Page views, oldest first, because a digest numbers its Pages. The
  caller reads the Chronicle and hands the views over; which of them a role sees
  and how each one reads is decided here, behind the seam, so that no caller has
  to pick a flavour of digest and no adapter has to remember a rule.

  There are two readers. The Author reads the Chronicle as it was played, grades
  and all, and naming a Room reads it the same way. The Scribe reads it with
  every recap and callback it has already written folded in, and with no grade
  anywhere: the closeness never crosses to the Scribe (ADR-0006), whether it is
  tonight's Page or one from last month.
  """

  @empty "Nothing yet; this is the first Page."

  @doc """
  The Chronicle as the Author reads it before writing Bookends, and as the
  Scribe reads each earlier Room's Chronicle before naming the next one.

  Recaps stay out. What a callback is allowed to touch is the Chronicle and
  nothing else: tonight's candy cane may turn up in next month's recap, and it
  may not quietly become next month's Bookends.
  """
  @spec author([map()]) :: String.t()
  def author(views), do: compose(views, :author)

  @doc """
  The Chronicle as the Scribe reads it before writing a recap.

  A callback is a line that remembers an earlier evening, so the Scribe sees the
  evenings it has already written about, including its own prose, so that it
  does not plant the same callback twice. It sees bands and reasoning and never
  a closeness: not a Verdict's, not the meld's, and not the one an overrule
  proposed.
  """
  @spec scribe([map()]) :: String.t()
  def scribe(views), do: compose(views, :scribe)

  defp compose([], _reader), do: @empty

  defp compose(views, reader) do
    views
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {page, index} -> page(page, index, reader) end)
  end

  defp page(page, index, reader) do
    bookends = Enum.join(page.bookends, " · ")

    lines = ["Page #{index} (#{bookends})#{gives(page)} — #{outcome(page, reader)}"]

    attempt_lines = Enum.flat_map(page.attempts, &attempt(&1, reader))
    overrule_lines = Enum.map(page.overrules, &overrule(&1, reader))
    correction_lines = Enum.map(page.corrections, &correction/1)

    Enum.join(
      lines ++ attempt_lines ++ overrule_lines ++ correction_lines ++ recap(page, reader),
      "\n"
    )
  end

  defp outcome(%{melded: true} = page, reader) do
    last_attempt = List.last(page.attempts)
    last_verdict = last_attempt && List.first(last_attempt.verdicts)
    band = last_verdict && last_verdict.band

    case reader do
      :author ->
        band_str = (band && ", #{band}") || ""
        "Melded on attempt #{last_attempt.number} (closeness: #{page.closeness}#{band_str})"

      :scribe ->
        band_str = (band && " (#{band})") || ""
        "Melded on attempt #{last_attempt.number}#{band_str}"
    end
  end

  defp outcome(page, _reader), do: "Unmelded after #{length(page.attempts)} attempts"

  defp gives(%{gives: []}), do: ""

  defp gives(page) do
    " [" <> Enum.map_join(page.gives, ", ", &give/1) <> "]"
  end

  defp give(%{seat_name: nil} = g), do: "Give: #{g.text}"
  defp give(g), do: "Give (#{g.seat_name}): #{g.text}"

  defp attempt(attempt, reader) do
    bridges = Enum.map_join(attempt.bridges, ", ", &~s(#{&1.seat_name} bridged "#{&1.bridge}"))

    case attempt.verdicts do
      [] ->
        ["  Attempt #{attempt.number}: #{bridges}. Verdict: Ungraded"]

      [single] ->
        ["  Attempt #{attempt.number}: #{bridges}. Verdict: #{verdict(single, reader)}"]

      # An attempt written before ADR-0010, when the Assayer answered one pair at
      # a time. The book is append-only, so those rows are still read out the way
      # they were written.
      multiple ->
        pair_lines =
          Enum.map(multiple, fn verdict ->
            "    Pair [#{Enum.join(verdict.bridges, " / ")}]: #{verdict(verdict, reader)}"
          end)

        ["  Attempt #{attempt.number}: #{bridges}." | pair_lines]
    end
  end

  defp verdict(verdict, :author) do
    band = (verdict.band && " (#{verdict.band})") || ""
    "#{verdict.closeness}#{band}#{reasoning(verdict)}"
  end

  defp verdict(verdict, :scribe), do: "#{verdict.band || "graded"}#{reasoning(verdict)}"

  defp reasoning(verdict), do: (verdict.reasoning && " — #{verdict.reasoning}") || ""

  defp overrule(overrule, :author),
    do:
      "  Overruled: #{overrule.proposer_name} proposed overrule to #{overrule.couple_closeness} (\"#{overrule.couple_reasoning}\")"

  defp overrule(overrule, :scribe),
    do:
      "  Overruled: #{overrule.proposer_name} proposed an overrule (\"#{overrule.couple_reasoning}\")"

  defp correction(correction) do
    original = (correction.original_value && " from \"#{correction.original_value}\"") || ""
    note = (correction.note && " (\"#{correction.note}\")") || ""

    "  Correction by #{correction.author_name}: corrected #{correction.target}#{original} to \"#{correction.corrected_value}\"#{note}"
  end

  defp recap(%{recap: %{recap: recap} = written}, :scribe) when is_binary(recap) do
    ["  Recap: #{recap}"] ++
      if(is_binary(written.callback), do: ["  Callback: #{written.callback}"], else: [])
  end

  defp recap(_page, _reader), do: []
end
