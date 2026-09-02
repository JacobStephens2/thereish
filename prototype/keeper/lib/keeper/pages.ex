defmodule Keeper.Pages do
  @moduledoc """
  Author JSON -> the Stage 0 Page shape (ids, ring, shuffled cards, exemplars); deterministic validation
  of Author output (counts, legality, disjointness); and clover grading, which needs no model at all.
  """

  alias Keeper.Legality

  # --- validation of the Author's JSON ----------------------------------------

  def validate(:clover, %{"clovers" => %{"A" => a, "B" => b}}) do
    with :ok <- validate_clover("A", a), :ok <- validate_clover("B", b) do
      overlap = MapSet.intersection(MapSet.new(down(a["words"])), MapSet.new(down(b["words"]))) |> MapSet.to_list()
      if overlap == [], do: :ok, else: {:error, "the two clovers share keywords: #{Enum.join(overlap, ", ")}"}
    end
  end

  def validate(:clover, _), do: {:error, "missing clovers A and B"}

  def validate(:mindmeld, %{"anchors" => [a, b]}) do
    cond do
      !(Legality.single_word?(a) and Legality.single_word?(b)) -> {:error, "anchors must be single lowercase words"}
      String.downcase(a) == String.downcase(b) -> {:error, "anchors must differ"}
      true -> :ok
    end
  end

  def validate(:mindmeld, _), do: {:error, "anchors must be exactly two words"}

  defp validate_clover(seat, %{"words" => words, "pairs" => pairs, "decoy" => decoy}) when is_list(words) and is_list(pairs) do
    cond do
      length(words) != 4 -> {:error, "#{seat}: need exactly four keywords, got #{length(words)}"}
      length(Enum.uniq(down(words))) != 4 -> {:error, "#{seat}: keywords repeat"}
      !Enum.all?(words, &Legality.single_word?/1) -> {:error, "#{seat}: keywords must be single lowercase words"}
      length(pairs) != 4 -> {:error, "#{seat}: need exactly four pairs, got #{length(pairs)}"}
      !Legality.single_word?(decoy["word"]) -> {:error, "#{seat}: decoy must be a single word"}
      String.downcase(decoy["word"]) in down(words) -> {:error, "#{seat}: the decoy repeats a keyword"}
      decoy["targets_pair"] not in 1..4 -> {:error, "#{seat}: decoy.targets_pair must be 1-4"}
      true -> check_clues(seat, words, pairs)
    end
  end

  defp validate_clover(seat, _), do: {:error, "#{seat}: malformed clover"}

  defp check_clues(seat, words, pairs) do
    pairs
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {%{"clue" => clue}, i}, {:ok, used} ->
      pair = [Enum.at(words, i), Enum.at(words, rem(i + 1, 4))]

      case Legality.check_clue(clue, pair, used) do
        :ok -> {:cont, {:ok, [String.downcase(clue) | used]}}
        {:illegal, why} -> {:halt, {:error, "#{seat}: clue #{i + 1} \"#{clue}\" for #{inspect(pair)} is illegal: #{why}"}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      err -> err
    end
  end

  defp down(words), do: Enum.map(words, &String.downcase(to_string(&1)))

  # --- Author JSON -> Page ---------------------------------------------------

  def from_author(:clover, json, give, seed) do
    id = page_id(json, seed)

    %{
      "id" => id,
      "kind" => "clover",
      "theme" => json["theme"],
      "give" => give,
      "clovers" => %{"A" => build_clover("A", json["clovers"]["A"], seed), "B" => build_clover("B", json["clovers"]["B"], seed + 1)}
    }
  end

  def from_author(:mindmeld, json, give, seed) do
    %{
      "id" => page_id(json, seed),
      "kind" => "mindmeld",
      "theme" => json["theme"],
      "give" => give,
      "anchors" => down(json["anchors"]),
      "likely_bridges" => down(json["likely_bridges"] || []),
      "why_these" => json["why_these"]
    }
  end

  defp page_id(json, seed), do: "P" <> (:erlang.phash2({json, seed}) |> Integer.to_string(36) |> String.slice(0, 6))

  defp build_clover(seat, c, seed) do
    words = down(c["words"])
    cards = words |> Enum.with_index() |> Enum.map(fn {w, i} -> %{"id" => "#{seat}#{i}", "word" => w} end)
    ring = Enum.map(cards, & &1["id"])
    t = c["decoy"]["targets_pair"] - 1

    decoy = %{
      "id" => seat <> "D",
      "word" => String.downcase(c["decoy"]["word"]),
      "targets_pair" => t,
      "rationale" =>
        "Crafted to sit plausibly under the clue for pair #{t + 1} (\"#{Enum.at(words, t)}\" / \"#{Enum.at(words, rem(t + 1, 4))}\"). " <>
          "Tempts: #{c["decoy"]["why_it_tempts"]} Excluded: #{c["decoy"]["why_the_bridge_excludes_it"]}"
    }

    :rand.seed(:exsss, {seed, seed * 7 + 1, seed * 13 + 2})
    shuffled = Enum.shuffle(ring ++ [decoy["id"]])

    %{
      "cards" => cards ++ [decoy],
      "ring" => ring,
      "decoy" => decoy,
      "shuffled" => shuffled,
      "exemplars" => Enum.map(c["pairs"], &String.downcase(&1["clue"])),
      "bridges" => Enum.map(c["pairs"], & &1["bridge"])
    }
  end

  # --- clover grading: deterministic, ported from Stage 0 ---------------------

  def grade_clover(page, %{"clues" => clues, "placements" => placements}) do
    {per, total, fell} =
      Enum.reduce(["A", "B"], {%{}, 0, []}, fn seat, {per, total, fell} ->
        guesser = other(seat)
        clover = page["clovers"][seat]
        placed = placements[guesser]
        ring = clover["ring"]

        graded =
          ring
          |> Enum.with_index()
          |> Enum.map(fn {_id, i} ->
            want = [Enum.at(ring, i), Enum.at(ring, rem(i + 1, 4))]
            got = [Enum.at(placed, i), Enum.at(placed, rem(i + 1, 4))]
            hits = Enum.zip(want, got) |> Enum.count(fn {w, g} -> w == g end)
            grade = case hits, do: (2 -> 3; 1 -> 1; _ -> 0)

            %{
              "slot" => i,
              "clue" => Enum.at(clues[seat], i),
              "grade" => grade,
              "reason" =>
                case hits do
                  2 -> "Both keywords landed where the clue pointed."
                  1 -> "Half-landed: one keyword right, one adrift."
                  _ -> "The clue pointed somewhere neither card went."
                end
            }
          end)

        fell = if clover["decoy"]["id"] in placed, do: fell ++ [guesser], else: fell
        {Map.put(per, seat, graded), total + Enum.sum(Enum.map(graded, & &1["grade"])), fell}
      end)

    ladder =
      cond do
        total == 24 -> "Telepathy, verified"
        total >= 20 -> "Two minds, one clover"
        total >= 15 -> "Well met"
        total >= 9 -> "Crossed wires"
        true -> "Strangers in the same house"
      end

    %{
      "kind" => "clover",
      "per" => per,
      "total" => total,
      "max" => 24,
      "fellForDecoy" => fell,
      "ladder" => ladder,
      "reasoning" =>
        "Graded per clue-pair, 3 for both keywords, 1 for a half-landing." <>
          if(fell == [], do: " Neither of you took the decoy.", else: " The authored decoy was placed by #{Enum.join(fell, " and ")}."),
      "orderings" => "deterministic; no model consulted",
      "model" => "none",
      "prompt_version" => Keeper.Prompts.version()
    }
  end

  defp other("A"), do: "B"
  defp other("B"), do: "A"
end
