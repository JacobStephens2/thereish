defmodule Keeper.Prompts do
  @moduledoc """
  Prompts and JSON schemas for the three roles. The version string is part of every cache key.
  Schemas are Jason.OrderedObject so property order on the wire is deliberate: reasoning before the number
  (answer-first JSON is where mid-tier judges lose points; see docs/research/model-selection-for-play.md §3e).
  """

  @version "v1"
  def version, do: @version

  defp o(pairs), do: Jason.OrderedObject.new(pairs)

  @doc "Recursively turn OrderedObjects into plain maps (for the validator)."
  def to_map(%Jason.OrderedObject{values: vs}), do: Map.new(vs, fn {k, v} -> {k, to_map(v)} end)
  def to_map(list) when is_list(list), do: Enum.map(list, &to_map/1)
  def to_map(other), do: other

  # --- Assayer ---------------------------------------------------------------

  def verdict_schema do
    o([
      {"type", "object"},
      {"properties",
       o([
         {"reasoning", o([{"type", "string"}, {"description", "One sentence, under 30 words."}])},
         {"closeness", o([{"type", "integer"}, {"description", "0 to 100"}])}
       ])},
      {"required", ["reasoning", "closeness"]},
      {"additionalProperties", false}
    ])
  end

  @assayer_system """
  You are the Assayer for Mind-Meld, a two-player word game. Two players saw the same two anchor words and each secretly wrote one bridging word that sits between the anchors in meaning. You measure how close the two bridging words landed to each other, not whether either bridge was clever or apt.

  Grade closeness from 0 to 100:
  - 100: the same word, or a plain inflection of it (tide / tides).
  - 75 to 99: the same idea in different words; the players melded.
  - 40 to 74: related but distinct ideas, or the same sense in only one reading.
  - 0 to 39: different roads; the words share little beyond the anchors.

  Write one short sentence of reasoning (under 30 words), then the grade. Measure meaning-distance only; ignore spelling, length and wordplay. Identical inputs must get identical grades, and the order in which the players are listed must not matter.
  """

  def assay(anchors, first, second) do
    [a, b] = anchors

    %{
      role: :assayer,
      system: @assayer_system,
      user: "Anchors: #{String.upcase(a)} and #{String.upcase(b)}.\nPlayer one bridged with: #{first}\nPlayer two bridged with: #{second}",
      schema: verdict_schema(),
      schema_name: "verdict"
    }
  end

  def check_verdict(%{"closeness" => c, "reasoning" => r}) when is_integer(c) and c >= 0 and c <= 100 and is_binary(r) and r != "", do: :ok
  def check_verdict(_), do: {:error, "closeness must be an integer 0-100 and reasoning a non-empty sentence"}

  # --- Author ----------------------------------------------------------------

  def clover_schema do
    o([
      {"type", "object"},
      {"properties",
       o([
         {"theme", o([{"type", "string"}, {"description", "The meaning-space this Page explores, in a few words."}])},
         {"clovers",
          o([
            {"type", "object"},
            {"properties", o([{"A", o([{"$ref", "#/$defs/clover"}])}, {"B", o([{"$ref", "#/$defs/clover"}])}])},
            {"required", ["A", "B"]},
            {"additionalProperties", false}
          ])}
       ])},
      {"required", ["theme", "clovers"]},
      {"additionalProperties", false},
      {"$defs",
       o([
         {"clover",
          o([
            {"type", "object"},
            {"properties",
             o([
               {"words", o([{"type", "array"}, {"items", o([{"type", "string"}])}, {"description", "Exactly four keywords, in ring order."}])},
               {"pairs", o([{"type", "array"}, {"items", o([{"$ref", "#/$defs/pair"}])}, {"description", "Exactly four: pairs (1,2), (2,3), (3,4), (4,1)."}])},
               {"decoy", o([{"$ref", "#/$defs/decoy"}])}
             ])},
            {"required", ["words", "pairs", "decoy"]},
            {"additionalProperties", false}
          ])},
         {"pair",
          o([
            {"type", "object"},
            {"properties",
             o([
               {"bridge", o([{"type", "string"}, {"description", "The connection the clue rides on."}])},
               {"clue", o([{"type", "string"}, {"description", "One legal word."}])}
             ])},
            {"required", ["bridge", "clue"]},
            {"additionalProperties", false}
          ])},
         {"decoy",
          o([
            {"type", "object"},
            {"properties",
             o([
               {"word", o([{"type", "string"}])},
               {"targets_pair", o([{"type", "integer"}, {"description", "1 to 4: which pair's clue the decoy tempts under."}])},
               {"why_it_tempts", o([{"type", "string"}])},
               {"why_the_bridge_excludes_it", o([{"type", "string"}])}
             ])},
            {"required", ["word", "targets_pair", "why_it_tempts", "why_the_bridge_excludes_it"]},
            {"additionalProperties", false}
          ])}
       ])}
    ])
  end

  def mindmeld_schema do
    o([
      {"type", "object"},
      {"properties",
       o([
         {"theme", o([{"type", "string"}])},
         {"anchors", o([{"type", "array"}, {"items", o([{"type", "string"}])}, {"description", "Exactly two single words."}])},
         {"likely_bridges", o([{"type", "array"}, {"items", o([{"type", "string"}])}, {"description", "Three to six bridging words you foresee."}])},
         {"why_these", o([{"type", "string"}])}
       ])},
      {"required", ["theme", "anchors", "likely_bridges", "why_these"]},
      {"additionalProperties", false}
    ])
  end

  @clover_system """
  You are the Author for a two-player couch word game played by Jacob and Mara. Tonight's Page is Chronicle Clover.

  How a Page works. Each player holds a clover of four keyword cards in a ring, so there are four adjacent pairs: (1,2), (2,3), (3,4), (4,1). A player writes one one-word clue per pair that binds both keywords, then hands the other player the four clues and the cards, the four real ones plus one decoy, shuffled. The partner rebuilds the ring from the clues. A clue is legal when it is a single word of letters only, is not either keyword, does not share its first four letters with either keyword, and is not reused within the same clover.

  Your job. Build both clovers for the theme you are given. For each pair write an exemplar clue and the bridge it rides on; the exemplars are never shown to the players, they are the Author's own pre-grading, and they must be legal. Craft one decoy per clover: a fifth keyword that a guesser could plausibly place under the exemplar clue of one target pair, so it tempts, but which that pair's two keywords, taken together, exclude on reflection. This is fair misdirection: the trap must be visible in hindsight and fun to narrate afterwards, never a coin flip. Keep the two clovers' keywords disjoint, and keep the decoy distinct from every keyword. Keywords are common single English words, lowercase, concrete enough to clue. Let the theme colour the whole vocabulary rather than listing its most obvious objects.
  """

  @mindmeld_system """
  You are the Author for a two-player couch word game played by Jacob and Mara. Tonight's Page is Mind-Meld.

  How a Page works. Both players see the same two anchor words. Each secretly writes one bridging word that sits between the anchors in meaning; at the reveal, the Assayer measures how close the two bridges landed to each other. If they meld (closeness 75 or more) the Page is won; otherwise the two bridges become the next anchors and the players try again, up to five attempts.

  Your job. Choose the opening anchor pair for the theme you are given. The best anchors are two ordinary single words with several plausible bridges between them pulling in different directions, so two minds can start apart and converge: not a pair with one obvious answer, and not a pair with no shared ground. List the bridges you foresee and say why this pair invites interesting divergence.
  """

  def author(:clover, give, digest), do: %{role: :author, kind: :clover, system: @clover_system, user: author_user(give, digest), schema: clover_schema(), schema_name: "clover_page"}
  def author(:mindmeld, give, digest), do: %{role: :author, kind: :mindmeld, system: @mindmeld_system, user: author_user(give, digest), schema: mindmeld_schema(), schema_name: "mindmeld_page"}

  defp author_user(give, digest) do
    give_line =
      case give do
        nil -> "No Give tonight: choose a meaning-space yourself, something a couple in Philadelphia might enjoy on a weeknight, and name it in `theme`."
        g -> "Give (tonight's theme, supplied by a player): #{g}"
      end

    "#{give_line}\n\nChronicle digest (what the machine remembers of past Pages):\n#{digest || "Nothing yet; this is the first Page."}"
  end

  # --- Scribe ----------------------------------------------------------------

  def scribe_schema, do: o([{"type", "object"}, {"properties", o([{"recap", o([{"type", "string"}])}])}, {"required", ["recap"]}, {"additionalProperties", false}])

  @scribe_system """
  You are the Scribe of a two-player couch word game played by Jacob and Mara. After a Page, write the single sentence the next Page opens with, beginning "Last time," : a callback in plain, warm, specific prose a couple would enjoy hearing read aloud. No emoji, no exclamation marks, no em dashes.
  """

  def scribe(page, verdict) do
    %{
      role: :scribe,
      system: @scribe_system,
      user: "The Page:\n#{Jason.encode!(page, pretty: true)}\n\nThe verdict:\n#{Jason.encode!(verdict, pretty: true)}",
      schema: scribe_schema(),
      schema_name: "recap"
    }
  end
end
