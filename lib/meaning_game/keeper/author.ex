defmodule MeaningGame.Keeper.Author do
  @moduledoc """
  The Author role: pre-generates Pages ahead of play against a named Chapter.

  The Author creates the opening Anchors, the Bait (obvious bridge), at least
  two deep Bridges, likely Bridges with `why_these` as the pre-graded table,
  and fallback band scripts. Contract shapes come from `prototype/keeper/REPORT.md`.
  """

  alias MeaningGame.Keeper.Legality

  @version "author-1"

  def version, do: @version

  @doc "The JSON schema the Author's responses must satisfy."
  def schema do
    o([
      {"type", "object"},
      {"properties",
       o([
         {"theme",
          o([
            {"type", "string"},
            {"description", "The meaning-space this Page explores, in a few words."}
          ])},
         {"anchors",
          o([
            {"type", "array"},
            {"items", o([{"type", "string"}])},
            {"description", "Exactly two single lowercase words."}
          ])},
         {"bait",
          o([
            {"type", "string"},
            {"description",
             "The obvious bridge both players will reach for: the lowest-rung meld."}
          ])},
         {"deep_bridges",
          o([
            {"type", "array"},
            {"items", o([{"type", "string"}])},
            {"description", "At least two deeper, subtler bridges that reward reflection."}
          ])},
         {"likely_bridges",
          o([
            {"type", "array"},
            {"items", o([{"type", "string"}])},
            {"description",
             "Three to eight bridging words you foresee, including bait and deep bridges."}
          ])},
         {"why_these",
          o([
            {"type", "string"},
            {"description",
             "Why these Anchors invite interesting divergence, narrating the misdirection."}
          ])},
         {"band_scripts",
          o([
            {"type", "object"},
            {"properties",
             o([
               {"miss", o([{"type", "string"}])},
               {"adjacent", o([{"type", "string"}])},
               {"near", o([{"type", "string"}])},
               {"meld", o([{"type", "string"}])},
               {"deep_meld", o([{"type", "string"}])}
             ])},
            {"required", ["miss", "adjacent", "near", "meld", "deep_meld"]},
            {"additionalProperties", false}
          ])}
       ])},
      {"required",
       [
         "theme",
         "anchors",
         "bait",
         "deep_bridges",
         "likely_bridges",
         "why_these",
         "band_scripts"
       ]},
      {"additionalProperties", false}
    ])
  end

  defp o(values), do: %Jason.OrderedObject{values: values}

  @doc "Validates the Author JSON against the schema with JSV."
  def check_schema(json) do
    case JSV.validate(json, validator()) do
      {:ok, _} ->
        :ok

      {:error, err} ->
        {:error,
         "schema: " <> (err |> JSV.normalize_error() |> Jason.encode!() |> String.slice(0, 600))}
    end
  end

  defp validator do
    key = {__MODULE__, :schema_validator}

    case :persistent_term.get(key, nil) do
      nil ->
        v = schema() |> to_map() |> JSV.build!()
        :persistent_term.put(key, v)
        v

      v ->
        v
    end
  end

  defp to_map(%Jason.OrderedObject{values: values}),
    do: Map.new(values, fn {key, value} -> {key, to_map(value)} end)

  defp to_map(list) when is_list(list), do: Enum.map(list, &to_map/1)
  defp to_map(other), do: other

  @doc """
  Deterministic gate: checks schema, legality of anchors and bridges,
  presence of bait and deep bridges in likely_bridges, and band scripts.
  """
  def check(json) do
    with :ok <- check_schema(json),
         :ok <- check_anchors(json["anchors"]),
         :ok <- check_bait(json["bait"], json["anchors"]),
         :ok <- check_deep_bridges(json["deep_bridges"], json["anchors"]),
         :ok <-
           check_likely_bridges(
             json["likely_bridges"],
             json["anchors"],
             json["bait"],
             json["deep_bridges"]
           ) do
      :ok
    end
  end

  defp check_anchors([a, b]) when is_binary(a) and is_binary(b) do
    a_down = String.downcase(String.trim(a))
    b_down = String.downcase(String.trim(b))

    cond do
      a_down == b_down ->
        {:error, "anchors must differ"}

      Legality.shared_root?(a_down, b_down) ->
        {:error, "anchors \"#{a}\" and \"#{b}\" share a root"}

      !Legality.single_word?(a_down) or !Legality.single_word?(b_down) ->
        {:error, "anchors must be single lowercase words"}

      !Legality.in_dictionary?(a_down) ->
        {:error, "anchor \"#{a}\" is not in the dictionary"}

      !Legality.in_dictionary?(b_down) ->
        {:error, "anchor \"#{b}\" is not in the dictionary"}

      Legality.profane?(a_down) or Legality.profane?(b_down) ->
        {:error, "anchors must not be profane"}

      true ->
        :ok
    end
  end

  defp check_anchors(_), do: {:error, "anchors must be a list of exactly two words"}

  defp check_bait(bait, anchors) do
    case Legality.check_bridge(bait, anchors) do
      :ok -> :ok
      {:illegal, why} -> {:error, "bait: #{why}"}
    end
  end

  defp check_deep_bridges(deep_bridges, anchors) when is_list(deep_bridges) do
    if length(deep_bridges) < 2 do
      {:error, "deep_bridges must have at least two words"}
    else
      Enum.reduce_while(deep_bridges, :ok, fn bridge, :ok ->
        case Legality.check_bridge(bridge, anchors) do
          :ok -> {:cont, :ok}
          {:illegal, why} -> {:halt, {:error, "deep bridge \"#{bridge}\": #{why}"}}
        end
      end)
    end
  end

  defp check_deep_bridges(_, _), do: {:error, "deep_bridges must be a list of words"}

  defp check_likely_bridges(likely, anchors, bait, deep) when is_list(likely) do
    down_likely = Enum.map(likely, &String.downcase(String.trim(&1)))
    down_bait = String.downcase(String.trim(bait))
    down_deep = Enum.map(deep, &String.downcase(String.trim(&1)))

    cond do
      down_bait not in down_likely ->
        {:error, "bait \"#{bait}\" must be in likely_bridges"}

      !Enum.all?(down_deep, &(&1 in down_likely)) ->
        {:error, "all deep_bridges must be included in likely_bridges"}

      true ->
        Enum.reduce_while(likely, :ok, fn bridge, :ok ->
          case Legality.check_bridge(bridge, anchors) do
            :ok -> {:cont, :ok}
            {:illegal, why} -> {:halt, {:error, "likely bridge \"#{bridge}\": #{why}"}}
          end
        end)
    end
  end

  defp check_likely_bridges(_, _, _, _), do: {:error, "likely_bridges must be a list"}

  @system_prompt """
  You are the Author for a two-player couch word game played by Jacob and Melissa. Tonight's game is Mind-Meld.

  How a Page works:
  Both players see the same two anchor words. Each secretly writes one bridging word that sits between the anchors in meaning; at the reveal, the Assayer measures how close the two bridges landed to each other. If they meld (closeness 75 or more) the Page is won; otherwise the two bridges become the next anchors and the players try again, up to five attempts.

  Your job:
  Build one Page for the theme / meaning-space you are given:
  1. Anchors: exactly two single common English lowercase words with shared meaning-space.
  2. Bait: the obvious, automatic bridge both players will immediately think of. Converging on the bait is a Meld on the lowest rung (75).
  3. Deep bridges: at least two deeper, subtler bridging words that reward reflection and land on the top rung (90+).
  4. Likely bridges: 3 to 8 bridging words you foresee players reaching for (must include the bait and the deep bridges).
  5. Why these: narrate the misdirection and why these Anchors invite interesting divergence.
  6. Band scripts: prewritten fallback remarks for each of the five ladder bands (miss, adjacent, near, meld, deep_meld).

  Legality rules (enforced strictly):
  - Every anchor, bait, and bridge must be a single, common lowercase English word (letters only, no spaces, hyphens, or punctuation).
  - The bait and every bridge must NEVER be either anchor and must NEVER share a root, stem, prefix, or inflection family with either anchor (e.g., if an anchor is "sing", "singer" and "song" are illegal).
  """

  @doc "Builds the request prompt for the Author."
  def prompt(chapter, give \\ nil, digest \\ nil) do
    user =
      "Theme / Chapter: #{chapter}\n" <>
        if(give, do: "Give: #{give}\n", else: "") <>
        "\nChronicle digest:\n#{digest || "Nothing yet; this is the first Page."}"

    %{
      role: :author,
      system: @system_prompt,
      user: user,
      schema: schema(),
      schema_name: "authored_page"
    }
  end

  @doc "Transforms validated Author JSON into an authored Page map."
  def page(json, chapter, give, answer) do
    id =
      answer[:id] ||
        "P" <>
          (:crypto.strong_rand_bytes(6)
           |> Base.encode32(case: :lower, padding: false)
           |> String.slice(0, 8))

    %{
      id: id,
      chapter: chapter,
      give: give,
      theme: json["theme"],
      anchors: Enum.map(json["anchors"], &String.downcase(String.trim(&1))),
      bait: String.downcase(String.trim(json["bait"])),
      deep_bridges: Enum.map(json["deep_bridges"], &String.downcase(String.trim(&1))),
      likely_bridges: Enum.map(json["likely_bridges"], &String.downcase(String.trim(&1))),
      why_these: json["why_these"],
      band_scripts: json["band_scripts"],
      meta: %{
        model: answer[:model] || "claude-fable-5-1",
        prompt_version: @version,
        attempts: answer[:attempts] || 1,
        cost_usd: answer[:cost_usd] || 0.0,
        latency_ms: answer[:latency_ms] || 0
      }
    }
  end

  @doc """
  Computes a provisional reading from the Author's likely_bridges table.
  """
  @spec provisional_reading(map(), String.t(), String.t()) :: atom()
  def provisional_reading(page, left, right) do
    left = String.downcase(String.trim(left || ""))
    right = String.downcase(String.trim(right || ""))

    bait = String.downcase(String.trim(page[:bait] || page["bait"] || ""))

    deep =
      Enum.map(
        page[:deep_bridges] || page["deep_bridges"] || [],
        &String.downcase(String.trim(&1))
      )

    likely =
      Enum.map(
        page[:likely_bridges] || page["likely_bridges"] || [],
        &String.downcase(String.trim(&1))
      )

    cond do
      left == right ->
        cond do
          left == bait -> :meld
          left in deep -> :deep_meld
          true -> :meld
        end

      left in likely and right in likely ->
        :near

      left in likely or right in likely ->
        :adjacent

      true ->
        :miss
    end
  end
end
