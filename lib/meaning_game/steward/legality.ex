defmodule MeaningGame.Steward.Legality do
  @moduledoc """
  Deterministic clue-legality gate (design law 14).

  Runs in pure Elixir: checks that every clue or bridge is a single word of
  letters only, present in the ENABLE dictionary, free of profanity, and
  does not share a stem, prefix, or inflection root with either bookend.

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

  @doc "Extracts the bridge text from a string, map, or struct."
  @spec bridge_text(term()) :: String.t()
  def bridge_text(%{bridge: b}) when is_binary(b), do: b
  def bridge_text(%{"bridge" => b}) when is_binary(b), do: b
  def bridge_text(%{text: t}) when is_binary(t), do: t
  def bridge_text(%{"text" => t}) when is_binary(t), do: t
  def bridge_text({_, b}) when is_binary(b), do: b
  def bridge_text(b) when is_binary(b), do: b
  def bridge_text(_), do: ""

  @doc "Trims, collapses internal whitespace, and downcases a bridge or phrase."
  @spec normalize_bridge(term()) :: String.t()
  def normalize_bridge(bridge) when is_binary(bridge) do
    bridge
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
    |> String.downcase()
  end

  def normalize_bridge(nil), do: ""
  def normalize_bridge(other), do: other |> to_string() |> normalize_bridge()

  @doc """
  Validates a player bridge against barred words and phrases (the bookends of
  every Attempt so far and every bridge committed in earlier attempts of this Page).

  Player bridges may be words or short phrases up to 40 characters containing
  letters, digits, spaces, hyphens, and apostrophes. Dictionary, single-word,
  and profanity checks are not applied to player bridges.
  """
  @spec check_bridge(term(), [term()]) :: :ok | {:illegal, String.t()}
  def check_bridge(bridge, barred_words \\ []) do
    clean = normalize_bridge(bridge)
    candidate = bridge |> to_string() |> String.trim()

    cond do
      clean == "" or String.match?(clean, ~r/^[^a-z0-9]+$/) ->
        {:illegal, "Write a word first."}

      !Regex.match?(~r/^[a-z0-9 '\-]+$/, clean) ->
        {:illegal, "Letters, digits, spaces, hyphens and apostrophes only (\"#{candidate}\")."}

      String.length(clean) > 40 ->
        {:illegal, "Too long to fit on a card."}

      true ->
        check_against_barred(clean, barred_words)
    end
  end

  @doc "Splits a phrase into component words, stripping punctuation boundaries."
  @spec extract_words(String.t()) :: [String.t()]
  def extract_words(text) when is_binary(text) do
    text
    |> String.split(~r/[\s\-]+/, trim: true)
    |> Enum.map(fn token -> String.replace(token, ~r/^'+|'+$/, "") end)
    |> Enum.reject(&(&1 == ""))
  end

  def extract_words(_), do: []

  defp check_against_barred(w, barred) do
    bridge_words = extract_words(w)

    Enum.find_value(barred, :ok, fn barred_item ->
      item_str = to_string(barred_item)
      item_norm = normalize_bridge(item_str)
      barred_words = extract_words(item_norm)

      cond do
        w == item_norm ->
          {:illegal, "\"#{w}\" shares a root with \"#{item_str}\"."}

        true ->
          Enum.find_value(bridge_words, fn bw ->
            Enum.find_value(barred_words, fn barred_word ->
              if shared_root?(bw, barred_word) do
                {:illegal, "\"#{w}\" shares a root with \"#{barred_word}\"."}
              end
            end)
          end)
      end
    end)
  end

  @doc """
  Whether two words share a stem or an inflection root.
  """
  @spec shared_root?(String.t(), String.t()) :: boolean()
  def shared_root?(w1, w2) do
    a = w1 |> to_string() |> String.trim() |> String.downcase()
    b = w2 |> to_string() |> String.trim() |> String.downcase()

    stem_a = stem_word(a)
    stem_b = stem_word(b)

    cond do
      a == b ->
        true

      stem_a == stem_b ->
        true

      prefix_overlap?(a, b, stem_a, stem_b) ->
        true

      inflection_match?(a, b) ->
        true

      true ->
        false
    end
  end

  defp stem_word(w) when is_binary(w) do
    case Stemmer.stem(w) do
      stem when is_binary(stem) -> stem
      [stem | _] when is_binary(stem) -> stem
      _ -> w
    end
  end

  defp prefix_overlap?(a, b, stem_a, stem_b) do
    (String.length(stem_a) >= 3 and String.starts_with?(b, stem_a)) or
      (String.length(stem_b) >= 3 and String.starts_with?(a, stem_b))
  end

  defp inflection_match?(a, b) do
    table = inflection_table()
    root_a = Map.get(table, a, a)
    root_b = Map.get(table, b, b)

    root_a == root_b or
      root_a == b or
      root_b == a or
      stem_word(root_a) == stem_word(b) or
      stem_word(root_b) == stem_word(a)
  end

  @doc """
  Every word the ENABLE dictionary holds.

  Public because a Room's Code is drawn from it (`MeaningGame.Rooms.Code`), and
  a second copy of the word list read from a second place is a second answer to
  "is this a word".
  """
  @spec dictionary() :: MapSet.t(String.t())
  def dictionary do
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
