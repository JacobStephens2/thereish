defmodule MeaningGame.Keeper.Assay do
  @moduledoc """
  What the Assayer is asked, and what counts as an answer.

  One system prompt, one JSON schema, one deterministic check, and a version
  string that rides on every verdict. The version is here rather than in
  configuration because it is a property of these words: change the question and
  the grades either side of the change are not comparable, and a precedent
  inherited from a different question is not the same precedent (ADR-0006).

  The schema's properties are in a deliberate order, and `reasoning` is first. A
  model that writes the number before its argument spends the argument defending
  a number it has already committed to, which is where mid-tier models lose
  points (`docs/research/model-selection-for-play.md`). The quip is last so that
  it can be about the grade.

  The Assayer grades and never rules. Nothing here asks it who won, whether the
  Page should end, or what the rung it landed on is called — the ladder is the
  game's (`MeaningGame.Ladder`) and the ruling is the couple's (design law 3).
  """

  @version "assay-1"

  @system """
  You are the Assayer for Mind-Meld, a two-player word game. Two players saw the same two anchor words and each secretly wrote one bridging word that sits between the anchors in meaning. You measure how close the two bridging words landed to each other, not whether either bridge was clever or apt.

  Grade closeness from 0 to 100:
  - 100: the same word, or a plain inflection of it (tide / tides).
  - 75 to 99: the same idea in different words; the players melded.
  - 40 to 74: related but distinct ideas, or the same sense in only one reading.
  - 0 to 39: different roads; the words share little beyond the anchors.

  Answer with one short sentence of reasoning (under 30 words), then the grade, then one line of comedy about the two words these two players actually wrote. The quip names both words, runs under 25 words, and is warm rather than cutting: the players are on the same side, and a miss is the joke rather than the sting. No emoji, no exclamation marks.

  Measure meaning-distance only; ignore spelling, length and wordplay. Identical inputs must get identical grades, and the order in which the players are listed must not matter.
  """

  @doc """
  The version of the question, carried on every verdict.

  Bump it whenever the system prompt or the schema changes.
  """
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  Everything one grading request is made of: the Anchors and the two Bridges, in
  the order they are to be shown to the model.

  The order is the caller's business rather than this module's, because both
  orderings get asked and the disagreement between them is a number the game
  keeps (design law 12).
  """
  @spec prompt([String.t()], String.t(), String.t()) :: map()
  def prompt([left_anchor, right_anchor], first, second) do
    %{
      system: @system,
      user:
        "Anchors: #{String.upcase(left_anchor)} and #{String.upcase(right_anchor)}.\n" <>
          "Player one bridged with: #{first}\n" <>
          "Player two bridged with: #{second}",
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
            {"description", "One sentence, under 30 words, on how close the two words landed."}
          ])},
         {"closeness", object([{"type", "integer"}, {"minimum", 0}, {"maximum", 100}])},
         {"quip",
          object([
            {"type", "string"},
            {"description", "One warm line of comedy naming both words the players wrote."}
          ])}
       ])},
      {"required", ["reasoning", "closeness", "quip"]},
      {"additionalProperties", false}
    ])
  end

  @doc """
  Whether a decoded answer is one the game may be shown.

  The schema has already had the last word on shape (design law 14); this is
  what a schema cannot say. Today that is only "a sentence of whitespace is not
  a sentence", which is a small thing to have a function for and exactly the
  kind of small thing a model does under a `minLength` of 1.
  """
  @spec check(map()) :: :ok | {:error, String.t()}
  def check(%{"reasoning" => reasoning, "quip" => quip})
      when is_binary(reasoning) and is_binary(quip) do
    if String.trim(reasoning) != "" and String.trim(quip) != "" do
      :ok
    else
      {:error, "reasoning and quip must each be a real sentence, not blank"}
    end
  end

  # Anything else is an answer the schema should already have turned away. It is
  # a rejection here rather than a `FunctionClauseError`, because this runs
  # inside a grading and a Page must never be lost to a shape nobody expected.
  def check(_answer), do: {:error, "the answer was missing a reasoning or a quip"}

  @doc """
  A verdict as the Room's rules take it, built from one graded ordering.

  Everything the model is trusted for is here and nothing else: how close, why,
  and the joke. The band, the meld, and what the Page does next are the game's.
  """
  @spec verdict(map()) :: %{closeness: integer(), reasoning: String.t(), quip: String.t()}
  def verdict(%{"closeness" => closeness, "reasoning" => reasoning, "quip" => quip}) do
    %{closeness: closeness, reasoning: String.trim(reasoning), quip: String.trim(quip)}
  end

  defp object(pairs), do: Jason.OrderedObject.new(pairs)
end
