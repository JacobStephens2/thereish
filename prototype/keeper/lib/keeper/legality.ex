defmodule Keeper.Legality do
  @moduledoc "Port of Stage 0's deterministic clue gate. A linter's job, never a model's (design law 14)."

  @profanity ~w(damn hell)

  @doc "check_clue(word, pair_words, used_clues) -> :ok | {:illegal, why}"
  def check_clue(word, pair_words, used_clues \\ []) do
    w = word |> to_string() |> String.trim() |> String.downcase()

    cond do
      w == "" -> {:illegal, "A clue needs a word."}
      !Regex.match?(~r/^[a-z]+$/, w) -> {:illegal, "One word, letters only (\"#{w}\")."}
      String.length(w) > 20 -> {:illegal, "Too long to fit on a card."}
      w in @profanity -> {:illegal, "Not at this table."}
      w in Enum.map(used_clues, &String.downcase(to_string(&1))) -> {:illegal, "Already used on this Page (\"#{w}\")."}
      true -> against_keywords(w, pair_words)
    end
  end

  defp against_keywords(w, pair_words) do
    Enum.find_value(pair_words, :ok, fn kw ->
      k = String.downcase(to_string(kw))

      cond do
        w == k -> {:illegal, "That is the keyword itself (\"#{kw}\")."}
        String.length(w) > 3 and String.length(k) > 3 and String.slice(w, 0, 4) == String.slice(k, 0, 4) -> {:illegal, "\"#{w}\" shares a root with \"#{kw}\"."}
        true -> nil
      end
    end)
  end

  def single_word?(w), do: is_binary(w) and Regex.match?(~r/^[a-z]+$/, String.downcase(String.trim(w)))
end
