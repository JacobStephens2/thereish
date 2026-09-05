defmodule MeaningGame.Steward.Assay do
  @moduledoc """
  What the Assayer is asked, and what counts as an answer.

  One system prompt, one JSON schema, one deterministic check, and a version
  string that rides on every verdict. The version is here rather than in
  configuration because it is a property of these words: change the question and
  the grades either side of the change are not comparable, and a precedent
  inherited from a different question is not the same precedent (ADR-0006).

  The Assayer reads every Bridge of an Attempt **together** and answers once
  (ADR-0010). It is asked how far the whole set is from being one mind, not how
  close any two of the words are, so that three tight words and one stray read as
  close rather than as a miss and a table of four gets a punchline rather than a
  report. At two Bridges that is the question the couch has always been asked.

  It is also asked which two Bridges landed furthest apart, because those two
  become the next Attempt's Bookends and the carry-forward should be something the
  players were told rather than something the game worked out behind them.

  The schema's properties are in a deliberate order, and `reasoning` is first. A
  model that writes the number before its argument spends the argument defending
  a number it has already committed to, which is where mid-tier models lose
  points (`docs/research/model-selection-for-play.md`). The quip is last so that
  it can be about the grade.

  The Assayer grades and never rules. Nothing here asks it who won, whether the
  Page should end, or what the rung it landed on is called — the ladder is the
  game's (`MeaningGame.Ladder`) and the ruling is the players' (design law 3).
  """

  alias MeaningGame.Steward.Precedent

  # Bumped from `assay-1` when the Assayer stopped grading pairs and started
  # grading sets (ADR-0010). The two questions are not the same question, so the
  # grades either side of the change are not comparable and no precedent crosses
  # it.
  @version "assay-2"

  @system """
  You are the Assayer for Mind-Meld, a word game played by two or more players. Every player saw the same two bookend words and each secretly wrote one bridging word that sits between the bookends in meaning. You measure how close the players' bridging words landed to one another, not whether any of them was clever or apt.

  Grade the whole set at once. The number is convergence: how far this set of words is from being one mind. Judge the set, not its worst pair — if most of the words say one thing and one wanders off, that is a set that mostly converged, not a miss. The same idea in different words is a meld. With exactly two words, this is simply how close those two landed.

  Grade convergence from 0 to 100:
  - 100: every word is the same word, or a plain inflection of it (tide / tides).
  - 75 to 99: the players melded — one idea, however many ways it was worded.
  - 40 to 74: related but distinct ideas, or one shared sense in only one reading.
  - 0 to 39: different roads; the words share little beyond the bookends.

  Answer with one short sentence of reasoning (under 30 words), then the grade, then the two words that landed furthest apart in meaning, then one line of comedy about the words these players actually wrote.

  The two furthest words must be exactly two of the bridging words you were given, copied exactly as they were written. If several pairs are equally far apart, pick any one of them.

  The quip names words the players wrote, runs under 25 words, and is warm rather than cutting: the players are on the same side, and a miss is the joke rather than the sting. No emoji, no exclamation marks.

  Measure meaning-distance only; ignore spelling, length and wordplay. Identical inputs must get identical grades, and the order in which the players are listed must not matter.
  """

  @doc """
  The version of the question, carried on every verdict.

  Bump it whenever the system prompt or the schema changes.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Everything one grading request is made of: the Bookends and every Bridge, in the
  order they are to be shown to the model.

  The order is the caller's business rather than this module's, because both
  orderings get asked and the disagreement between them is a number the game
  keeps (design law 12).
  """
  @spec prompt([String.t()], [String.t()]) :: map()
  def prompt([left_bookend, right_bookend], bridges) when is_list(bridges) do
    written =
      bridges
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {bridge, number} ->
        "Player #{number} bridged with: #{bridge}"
      end)

    %{
      system: @system,
      user:
        "Bookends: #{String.upcase(left_bookend)} and #{String.upcase(right_bookend)}.\n" <> written,
      schema: schema(),
      schema_name: "verdict"
    }
  end

  @doc """
  The shape of an answer, as the provider is asked for it.

  A `Jason.OrderedObject` rather than a map, because the order the properties
  are written in is the order the model tends to answer in, and that order is
  the point.
  """
  @spec schema() :: Jason.OrderedObject.t()
  def schema do
    object([
      {"type", "object"},
      {"properties",
       object([
         {"reasoning",
          object([
            {"type", "string"},
            {"description", "One sentence, under 30 words, on how close the words landed."}
          ])},
         {"closeness", object([{"type", "integer"}, {"minimum", 0}, {"maximum", 100}])},
         {"furthest",
          object([
            {"type", "array"},
            {"items", object([{"type", "string"}])},
            {"minItems", 2},
            {"maxItems", 2},
            {"description",
             "Exactly two of the bridging words given, copied verbatim: the two that landed furthest apart."}
          ])},
         {"quip",
          object([
            {"type", "string"},
            {"description", "One warm line of comedy naming words the players wrote."}
          ])}
       ])},
      {"required", ["reasoning", "closeness", "furthest", "quip"]},
      {"additionalProperties", false}
    ])
  end

  @doc """
  Whether a decoded answer is one the game may be shown.

  The schema has already had the last word on shape (design law 14); this is
  what a schema cannot say. Two things: a sentence of whitespace is not a
  sentence, and the two furthest-apart words have to be two of the words that
  were actually asked about.

  The second one matters more than it looks. Those two words become the next
  Attempt's Bookends, so a model that paraphrased a Bridge, or invented one, would
  send the table somewhere nobody wrote. They are compared after the same
  normalisation the Precedent keys on, so casing and stray whitespace are
  forgiven and nothing else is.
  """
  @spec check(map(), [String.t()]) :: :ok | {:error, String.t()}
  def check(%{"reasoning" => reasoning, "quip" => quip, "furthest" => furthest}, bridges)
      when is_binary(reasoning) and is_binary(quip) do
    cond do
      String.trim(reasoning) == "" or String.trim(quip) == "" ->
        {:error, "reasoning and quip must each be a real sentence, not blank"}

      not (is_list(furthest) and length(furthest) == 2) ->
        {:error, "furthest must name exactly two of the bridging words"}

      Enum.any?(furthest, &is_nil(resolve(&1, bridges))) ->
        {:error,
         "furthest must name two of the bridging words that were given: " <>
           Enum.map_join(bridges, ", ", &inspect/1)}

      true ->
        :ok
    end
  end

  # Anything else is an answer the schema should already have turned away. It is
  # a rejection here rather than a `FunctionClauseError`, because this runs
  # inside a grading and a Page must never be lost to a shape nobody expected.
  def check(_answer, _bridges),
    do: {:error, "the answer was missing a reasoning, a quip or a furthest pair"}

  @doc """
  A verdict as the Room's rules take it, built from one graded ordering.

  Everything the model is trusted for is here and nothing else: how close, why,
  which two words are furthest apart, and the joke. The band, the meld, and what
  the Page does next are the game's.

  The furthest pair is returned as the players wrote it rather than as the model
  echoed it back, because those two words are about to be shown as the next
  Attempt's Bookends and the words on the screen should be the words somebody
  typed.
  """
  @spec verdict(map(), [String.t()]) :: %{
          closeness: integer(),
          reasoning: String.t(),
          quip: String.t(),
          furthest: [String.t()]
        }
  def verdict(
        %{
          "closeness" => closeness,
          "reasoning" => reasoning,
          "quip" => quip,
          "furthest" => furthest
        },
        bridges
      ) do
    %{
      closeness: closeness,
      reasoning: String.trim(reasoning),
      quip: String.trim(quip),
      furthest: Enum.map(furthest, &resolve(&1, bridges))
    }
  end

  # Which Bridge the model meant, verbatim as it was written, or nil if it did
  # not mean any of them.
  defp resolve(word, bridges) when is_binary(word) do
    normalized = Precedent.normalize(word)

    Enum.find(bridges, fn bridge -> Precedent.normalize(bridge) == normalized end)
  end

  defp resolve(_word, _bridges), do: nil

  defp object(pairs), do: Jason.OrderedObject.new(pairs)
end
