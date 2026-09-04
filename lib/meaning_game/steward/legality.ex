defmodule MeaningGame.Steward.Legality do
  @moduledoc """
  Deterministic clue-legality gate (design law 14).

  Runs in pure Elixir: checks that every clue or bridge is a single word of
  letters only, present in the ENABLE dictionary, free of profanity, and
  does not share a stem, prefix, or inflection root with either anchor.

  Used on the phone before commit and on commit, and on the Author's output
  before any Page enters the pool.
  """

  @extra_profanity ~w(
    damn hell fuck shit bitch bastard ass piss dick cunt cock asshole
    motherfucker wank wanker bollocks twat
  )

  @doc "Whether a string is a single lowercase word of letters only."
  @spec single_word?(term()) :: boolean()
  def single_word?(word) when is_binary(word) do
    w = word |> String.trim() |> String.downcase()
    w != "" and Regex.match?(~r/^[a-z]+$/, w) and String.length(w) <= 30
  end

  def single_word?(_), do: false

  @doc "Whether a word is recognized in the ENABLE dictionary."
  @spec in_dictionary?(String.t()) :: boolean()
  def in_dictionary?(word) when is_binary(word) do
    w = word |> String.trim() |> String.downcase()
    MapSet.member?(dictionary(), w)
  end

  def in_dictionary?(_), do: false

  @doc "Whether a word contains or matches profanity."
  @spec profane?(String.t()) :: boolean()
  def profane?(word) when is_binary(word) do
    w = word |> String.trim() |> String.downcase()
    w in @extra_profanity or MapSet.member?(profanity_set(), w)
  end

  def profane?(_), do: false

  @doc """
  Validates a player or author bridge against the anchor words.

  Returns `:ok` or `{:illegal, reason}`.
  """
  @spec check_bridge(String.t(), [String.t()]) :: :ok | {:illegal, String.t()}
  def check_bridge(bridge, anchors) do
    w = bridge |> to_string() |> String.trim() |> String.downcase()

    cond do
      w == "" ->
        {:illegal, "Write a word first."}

      !Regex.match?(~r/^[a-z]+$/, w) ->
        {:illegal, "One word, letters only (\"#{w}\")."}

      String.length(w) > 30 ->
        {:illegal, "Too long to fit on a card."}

      profane?(w) ->
        {:illegal, "Not in this Room."}

      !in_dictionary?(w) ->
        {:illegal, "\"#{w}\" is not in the dictionary."}

      true ->
        check_against_anchors(w, anchors)
    end
  end

  @doc """
  Whether two words share a stem or an inflection root.
  """
  @spec shared_root?(String.t(), String.t()) :: boolean()
  def shared_root?(w1, w2) do
    a = w1 |> String.trim() |> String.downcase()
    b = w2 |> String.trim() |> String.downcase()

    cond do
      a == b ->
        true

      Stemmer.stem(a) == Stemmer.stem(b) ->
        true

      prefix_overlap?(a, b) ->
        true

      inflection_match?(a, b) ->
        true

      true ->
        false
    end
  end

  defp prefix_overlap?(a, b) do
    sa = Stemmer.stem(a)
    sb = Stemmer.stem(b)

    (String.length(sa) >= 3 and String.starts_with?(b, sa)) or
      (String.length(sb) >= 3 and String.starts_with?(a, sb))
  end

  defp inflection_match?(a, b) do
    table = inflection_table()
    root_a = Map.get(table, a, a)
    root_b = Map.get(table, b, b)

    root_a == root_b or
      root_a == b or
      root_b == a or
      Stemmer.stem(root_a) == Stemmer.stem(b) or
      Stemmer.stem(root_b) == Stemmer.stem(a)
  end

  defp check_against_anchors(w, anchors) do
    Enum.find_value(anchors, :ok, fn anchor ->
      a = anchor |> to_string() |> String.trim() |> String.downcase()

      cond do
        w == a ->
          {:illegal, "That is the anchor itself (\"#{anchor}\")."}

        shared_root?(w, a) ->
          {:illegal, "\"#{w}\" shares a root with \"#{anchor}\"."}

        true ->
          nil
      end
    end)
  end

  defp dictionary do
    key = {__MODULE__, :dictionary}

    case :persistent_term.get(key, nil) do
      nil ->
        words =
          priv_file("wordlists/enable1.txt")
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.map(&String.trim/1)
          |> MapSet.new()

        :persistent_term.put(key, words)
        words

      set ->
        set
    end
  end

  defp inflection_table do
    key = {__MODULE__, :inflections}

    case :persistent_term.get(key, nil) do
      nil ->
        table =
          priv_file("wordlists/inflections.txt")
          |> File.read!()
          |> String.split("\n", trim: true)
          |> Enum.reduce(%{}, fn line, acc ->
            case String.split(line, ~r/\s+/, trim: true) do
              [root | variants] ->
                Enum.reduce(variants, Map.put(acc, root, root), fn var, m ->
                  Map.put(m, var, root)
                end)

              _ ->
                acc
            end
          end)

        :persistent_term.put(key, table)
        table

      table ->
        table
    end
  end

  defp profanity_set do
    key = {__MODULE__, :profanity}

    case :persistent_term.get(key, nil) do
      nil ->
        set =
          try do
            Expletive.Blacklist.english()
            |> Enum.map(&String.downcase/1)
            |> MapSet.new()
          rescue
            _ -> MapSet.new()
          end

        :persistent_term.put(key, set)
        set

      set ->
        set
    end
  end

  defp priv_file(relative_path) do
    case :code.priv_dir(:meaning_game) do
      {:error, :bad_name} ->
        Path.join(["priv", relative_path])

      dir ->
        path = Path.join(dir, relative_path)
        if File.exists?(path), do: path, else: Path.join(["priv", relative_path])
    end
  end
end
