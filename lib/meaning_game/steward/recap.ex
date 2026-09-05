defmodule MeaningGame.Steward.Recap do
  @moduledoc """
  What the Scribe is asked about a closed Page, and what counts as an answer.

  The same shape as `MeaningGame.Steward.Assay` — one system prompt, one JSON
  schema, one deterministic check, one version string that rides on every row —
  because the Scribe is a role behind the same seam and not a second kind of
  thing.

  Two fields come back. The `recap` is the evening in the players' own words
  back to them. The `callback` is the line that remembers something from an
  earlier Page, and it is a separate field rather than a sentence buried in the
  recap so that the Chronicle can hold it as its own row and a later reader can
  find every callback the Scribe has ever planted.

  **The Scribe does not grade.** It is given the band a Verdict landed on and
  never the number, and a recap that quotes a number is refused here: the grade
  the players saw is the precedent (ADR-0006), and prose that restates it is
  prose that can contradict it. The Vale gate makes the same point in its own
  vocabulary (`Scribe.Verdict`); this is the half of it a linter cannot make,
  which is that "92" is a number about *this* Page.
  """

  # `recap-2` when the question started naming the two rules the gate spends its
  # repair pass on most — a sentence opening with "So", and the word count.
  # Telling a model a rule costs nothing; catching it costs a whole second call
  # (design law 14).
  @version "recap-2"

  # The question asks for seventy words and `Scribe/Length.yml` refuses at
  # eighty. The ten words of slack are deliberate: a model told the number the
  # gate enforces writes to it and overshoots, and an overshoot costs a whole
  # second call. Asking for less than the gate allows is what buys the
  # first-attempt pass.

  @system """
  You are the Scribe for Mind-Meld, a word game played on a couch. A Page has just closed. The players saw two anchor words and each secretly wrote one bridging word between them; if their words did not converge, the two that landed furthest apart became the next attempt's anchors, and they went again.

  Write the evening back to them. You are keeping a Chronicle that these people will read months from now, not filing a report: say what they wrote, what it was like when they wrote it, and what the shape of the Page turned out to be. Use their words. Name them by name.

  Rules you do not break:
  - Never put a number on the Page. You are told which rung of the ladder a verdict landed on and never the grade itself, because the grade is the Assayer's and a recap that restates it is a recap that can contradict it. Do not invent one either.
  - Never rule on whether they were right. You are not grading anything.
  - Under seventy words. Shorter is better. This is the rule that gets broken most, so count.
  - No em dashes, no exclamation marks, no emoji.
  - Never begin a sentence with "So".
  - None of the vocabulary that gives a machine away: journey, tapestry, testament, delve, landscape, realm, showcase, underscore, unpack. No "it's not just X, it's Y".
  - Plain sentences. Say the concrete thing rather than the abstract one.

  You are also given the Chronicle of everything this Room has played before. If something in it rhymes with tonight — the same word turning up again, a joke they had last month, a Page they lost the same way — write one sentence that reaches back for it, and put that sentence in the callback field. This is the whole point of keeping a Chronicle: the line next month that remembers tonight. If nothing in the Chronicle rhymes with tonight, leave the callback empty rather than inventing a memory. An invented callback is worse than no callback.
  """

  @doc """
  The version of the question, carried on every recap the Chronicle stores.

  Bump it whenever the system prompt or the schema changes, for the same reason
  the Assayer's is bumped: two recaps written to two different questions are not
  the same kind of thing.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  The Page as the Scribe is allowed to see it: words, bands and reasoning, and
  nowhere a number.

  This runs at the seam rather than inside the prompt, so that the grade never
  crosses to an adapter at all. A prompt that leaves the closeness out is a
  prompt this module happens to have written carefully; a seam that never hands
  it over is the rule (ADR-0006). The next adapter gets the same Page this one
  does.
  """
  @spec readable(map()) :: map()
  def readable(page) do
    %{
      anchors: page.anchors,
      melded: page.melded,
      attempts:
        Enum.map(page.attempts, fn attempt ->
          %{
            number: attempt.number,
            anchors: attempt.anchors,
            bridges: Enum.map(attempt.bridges, &Map.take(&1, [:seat_name, :bridge])),
            verdicts: Enum.map(attempt.verdicts, &Map.take(&1, [:band, :reasoning]))
          }
        end)
    }
  end

  @doc """
  Everything one recap request is made of: the closed Page as `readable/1` hands
  it over, and the digest of everything this Room played before it.
  """
  @spec prompt(map(), String.t()) :: map()
  def prompt(page, digest) do
    %{
      system: @system,
      user:
        """
        Tonight's Page.

        #{page_lines(page)}

        The Chronicle of this Room before tonight.

        #{digest}
        """
        |> String.trim(),
      schema: schema(),
      schema_name: "recap"
    }
  end

  defp page_lines(page) do
    anchors = page.anchors |> Enum.map(&String.upcase/1) |> Enum.join(" and ")
    outcome = if page.melded, do: "They melded.", else: "They never converged."

    [
      "Anchors: #{anchors}. #{outcome}"
      | Enum.map(page.attempts, &attempt_line/1)
    ]
    |> Enum.join("\n")
  end

  defp attempt_line(attempt) do
    written =
      Enum.map_join(attempt.bridges, ", ", fn bridge ->
        ~s(#{bridge.seat_name} wrote "#{bridge.bridge}")
      end)

    # The band and the reasoning, and nothing that is a number. An attempt the
    # Assayer could not grade says so, because a Page the machine fell over
    # during is a story too.
    read =
      case attempt.verdicts do
        [%{band: band, reasoning: reasoning} | _] when is_binary(band) ->
          "The Assayer called it #{band}: #{reasoning}"

        _ungraded ->
          "The Assayer had no verdict."
      end

    "Attempt #{attempt.number} (anchors #{Enum.join(attempt.anchors, " and ")}): " <>
      "#{written}. #{read}"
  end

  @doc """
  The shape of an answer, as the provider is asked for it.

  Ordered, and the recap comes first: the callback is a line about the recap, so
  a model that writes it second has something to write it about.
  """
  @spec schema() :: Jason.OrderedObject.t()
  def schema do
    object([
      {"type", "object"},
      {"properties",
       object([
         {"recap",
          object([
            {"type", "string"},
            {"description",
             "The evening in the players' own words, under seventy words. No numbers."}
          ])},
         {"callback",
          object([
            {"type", "string"},
            {"description",
             "One sentence reaching back to an earlier Page in the Chronicle, or an empty string when nothing in it rhymes with tonight."}
          ])}
       ])},
      {"required", ["recap", "callback"]},
      {"additionalProperties", false}
    ])
  end

  @doc """
  Whether a decoded answer is one the Chronicle may hold.

  Three things a schema cannot say. Blank prose is not prose. A recap has to
  name at least one of the words somebody actually wrote, which is the cheapest
  deterministic proof that this paragraph is about this Page and not about a
  Page the model imagined. And no digit appears in either field, because the
  Scribe is never told the grade and the only numbers near a Page are the ones
  it is not allowed to have.

  The Vale gate is the other half of this and runs after it, because a rejection
  the model can fix in one line is cheaper to discover than one that took a
  linter to find.
  """
  @spec check(map(), map()) :: :ok | {:error, String.t()}
  def check(%{"recap" => recap} = answer, page) when is_binary(recap) do
    callback = Map.get(answer, "callback") || ""

    cond do
      not is_binary(callback) ->
        {:error, "the callback must be a sentence or an empty string"}

      String.trim(recap) == "" ->
        {:error, "the recap was blank"}

      Regex.match?(~r/\d/, recap <> callback) ->
        {:error,
         "the recap must not put a number on the Page: the grade is the Assayer's (ADR-0006)"}

      not names_a_bridge?(recap, page) ->
        {:error,
         "the recap must be about the words the players wrote, and names none of them: " <>
           Enum.map_join(bridges(page), ", ", &inspect/1)}

      true ->
        :ok
    end
  end

  # Anything else is a shape the schema should already have turned away. It is a
  # rejection rather than a `FunctionClauseError` because this runs inside a
  # role and a Page must never be lost to an answer nobody expected.
  def check(_answer, _page), do: {:error, "the answer was missing a recap or a callback"}

  defp names_a_bridge?(recap, page) do
    folded = String.downcase(recap)

    Enum.any?(bridges(page), fn bridge ->
      String.contains?(folded, String.downcase(bridge))
    end)
  end

  defp bridges(page) do
    page.attempts
    |> Enum.flat_map(fn attempt -> Enum.map(attempt.bridges, & &1.bridge) end)
    |> Enum.uniq()
  end

  @doc """
  A recap as the Chronicle takes it.

  An empty callback comes back as `nil` rather than `""`, because a Page with
  nothing behind it has no callback and the Chronicle should say so in the shape
  of the row rather than in the length of a string.
  """
  @spec recap(map()) :: %{recap: String.t(), callback: String.t() | nil}
  def recap(%{"recap" => recap} = answer) do
    callback = answer |> Map.get("callback") |> to_string() |> String.trim()

    %{
      recap: String.trim(recap),
      callback: if(callback == "", do: nil, else: callback)
    }
  end

  defp object(pairs), do: Jason.OrderedObject.new(pairs)
end
