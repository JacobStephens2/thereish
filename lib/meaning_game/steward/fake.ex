defmodule MeaningGame.Steward.Fake do
  @moduledoc """
  An Assayer with no model behind it: the same verdict for the same Bridges,
  every time, at whatever speed the caller asked for.

  It grades on the letters two Bridges share from the front, which is not a
  measure of meaning and is not trying to be. It is a **dial**: a test that
  wants a Meld writes "cairn" and "cairo", one that wants a miss writes "cairn"
  and "beacon", and neither has to know anything about a model. Every test that
  is not a hand-run smoke test grades against this, so the numbers a test asserts
  on are the ones it chose.

  At more than two Bridges it stays a dial. The Closeness is the mean of that
  same shared-prefix grade over every pair, and the two words it names as
  furthest apart are the pair that scored lowest, ties going to whichever came
  first in roster order. At exactly two Bridges there is one pair, so the mean is
  that pair's grade and the furthest two are the only two — which is what makes
  every grade the couch's tests were written against still the grade they get
  (ADR-0010).

  Two knobs, both configuration, both for the tests that need the Room to be
  waiting on something:

      config :meaning_game, :steward, fake: [delay_ms: 0, mode: :grade]

  `delay_ms` is how long a verdict takes. `mode: :unavailable` is an Assayer
  that says it cannot answer, and `mode: :raise` is one that falls over without
  saying anything — the two shapes a failed grade comes in, both of which the
  game answers the same way.

  ## The other two roles

  The Author and the Scribe have the same dials under the same names —
  `author_mode`, `author_delay_ms`, `recap_mode`, `recap_delay_ms` — and the
  Scribe takes a `recap` and a `recap_callback` for a test that wants particular
  prose. Left alone, the fake Scribe writes the one true sentence about a Page
  out of the Bridges in it, and reaches back for a callback only when the digest
  it was handed has something in it, which is the same thing that decides it for
  the real one.
  """
  @behaviour MeaningGame.Steward

  @impl true
  def assay(%{bookends: [_, _], bridges: bridges}) when length(bridges) >= 2 do
    delay_ms() |> Process.sleep()

    case mode() do
      :grade -> {:ok, grade(bridges)}
      :unavailable -> {:error, :no_verdict}
      :raise -> raise "this Assayer is having a moment"
    end
  end

  @impl true
  def author(chapter, opts \\ []) do
    delay = author_delay_ms()
    if delay > 0, do: Process.sleep(delay)

    case author_mode() do
      :ok ->
        give = Keyword.get(opts, :give)
        %{bookends: bookends, bait: bait, deep_bridges: deep_bridges} = authored_bridges(give)
        likely_bridges = [bait | deep_bridges] ++ ["prayer", "faith"]

        json = %{
          "theme" => give || chapter,
          "bookends" => bookends,
          "bait" => bait,
          "deep_bridges" => deep_bridges,
          "likely_bridges" => likely_bridges,
          "why_these" => "The bookends invite #{bait} as the immediate trap.",
          "band_scripts" => default_band_scripts()
        }

        {:ok,
         MeaningGame.Steward.Author.page(json, chapter, give, %{
           model: "fake-author",
           attempts: 1,
           cost_usd: 0.0,
           latency_ms: delay
         })}

      :refused ->
        {:error, :refused}

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "this Author is having a moment"
    end
  end

  @impl true
  def recap(page, digest) do
    delay = config_get(:recap_delay_ms, 0)
    if delay > 0, do: Process.sleep(delay)

    case config_get(:recap_mode, :ok) do
      :ok ->
        {:ok,
         %{
           recap: config_get(:recap, nil) || written(page),
           callback: config_get(:recap_callback, nil) || remembered(digest),
           meta: %{
             model: "fake-scribe",
             prompt_version: "fake-recap-1",
             cost_usd: 0.0,
             latency_ms: delay,
             attempts: 1
           }
         }}

      :unavailable ->
        {:error, :no_recap}

      :timeout ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}

      :raise ->
        raise "this Scribe is having a moment"
    end
  end

  # The Scribe with no model behind it writes the one true sentence about a
  # Page: who wrote what, first and last. It is a dial like the grade is — a
  # test that wants a recap naming a word writes that word as a Bridge — and it
  # is deliberately prose the real Vale gate would pass, so that no test is ever
  # asserting on a paragraph the couch would never be shown.
  defp written(page) do
    first = List.first(page.attempts)
    last = List.last(page.attempts)

    opening = Enum.map_join(first.bridges, ", ", &~s(#{&1.seat_name} wrote "#{&1.bridge}"))
    closing = Enum.map_join(last.bridges, " and ", &~s("#{&1.bridge}"))

    ending = if page.melded, do: "They met at", else: "They ended on"

    "On the first attempt, #{opening}. #{ending} #{closing}."
  end

  # A callback needs a Chronicle to reach back into, and a Room playing its
  # first Page has none. The fake tells the two apart the same way the real
  # Scribe is asked to: by whether the digest has anything in it.
  defp remembered("Nothing yet" <> _rest), do: nil
  defp remembered(_digest), do: "They have been here before."

  @default_band_scripts %{
    "miss" => "Different neighbourhoods entirely.",
    "adjacent" => "On the same block, across the street.",
    "close" => "Passable.",
    "meld" => "You both saw the grill.",
    "deep_meld" => "Two minds at the mower."
  }

  @doc "Default band scripts used by the Fake author and test fixtures."
  def default_band_scripts, do: @default_band_scripts

  defp authored_bridges(nil) do
    %{
      bookends: ["backyard", "weekend"],
      bait: "barbecue",
      deep_bridges: ["lawnmower", "chores"]
    }
  end

  defp authored_bridges(give) do
    %{
      bookends: give_bookends(give),
      bait: "altar",
      deep_bridges: ["saint", "church"]
    }
  end

  defp give_bookends("hospital" <> _), do: ["nurse", "clinic"]
  defp give_bookends(_give), do: ["candle", "chapel"]

  defp author_delay_ms, do: config_get(:author_delay_ms, 0)
  defp author_mode, do: config_get(:author_mode, :ok)

  defp config_get(key, default) do
    :meaning_game
    |> Application.get_env(:steward, [])
    |> Keyword.get(:fake, [])
    |> Keyword.get(key, default)
  end

  defp grade(bridges) do
    graded = for pair <- every_pair(bridges), do: {pair, pair_closeness(pair)}
    closeness = graded |> Enum.map(&elem(&1, 1)) |> mean()

    # The pair the arithmetic liked least, which is this Assayer's whole idea of
    # two words having landed far apart. `min_by` keeps the first of a tie, and
    # the pairs come out in roster order, so a table that ties gets the same
    # answer every time it plays.
    {[left, right], _lowest} = Enum.min_by(graded, &elem(&1, 1))
    shared = shared_prefix(left, right)

    %{
      closeness: closeness,
      # The reasoning, the quip and the reverse reading all name the furthest
      # two, which at two Bridges is both of them: every sentence this Assayer
      # has ever written about a pair is the sentence it still writes.
      reasoning:
        "\"#{left}\" and \"#{right}\" share #{shared} letters from the front. " <>
          "That is all this Assayer knows how to look at.",
      # Named after the players' actual Bridges, like the live one's, so that
      # every screen the quip is drawn on is exercised by a test that never
      # calls anybody (ADR-0005).
      quip: "\"#{left}\" and \"#{right}\" walk into a bar. The bar has no opinion.",
      furthest: [left, right],
      # Provenance the Chronicle wants from every Assayer, answered honestly by
      # the one that has no model behind it and costs nothing to run. Both
      # orderings agree because this Assayer is a symmetric function of a set of
      # words: grading it twice is the same arithmetic twice.
      meta: %{
        model: "fake",
        prompt_version: "fake-1",
        cost_usd: 0.0,
        forward: closeness,
        reverse: closeness,
        reasoning_reverse:
          "\"#{right}\" and \"#{left}\" share the same #{shared} letters the other way round."
      }
    }
  end

  # Every unordered pair, in roster order, so that the tie-break is the order the
  # Seats are sitting in rather than the order a map happened to iterate.
  defp every_pair(bridges) do
    for {left, i} <- Enum.with_index(bridges),
        {right, j} <- Enum.with_index(bridges),
        i < j,
        do: [left, right]
  end

  defp pair_closeness([left, right]) do
    round(200 * shared_prefix(left, right) / (String.length(left) + String.length(right)))
  end

  # Rounded once at the end. At two Bridges there is one pair and rounding an
  # already-rounded number changes nothing, which is the point.
  defp mean(closenesses), do: round(Enum.sum(closenesses) / length(closenesses))

  defp shared_prefix(left, right) do
    left
    |> String.graphemes()
    |> Enum.zip(String.graphemes(right))
    |> Enum.take_while(fn {a, b} -> a == b end)
    |> length()
  end

  defp delay_ms, do: config(:delay_ms)

  defp mode, do: config(:mode)

  defp config(key) do
    :meaning_game
    |> Application.fetch_env!(:steward)
    |> Keyword.fetch!(:fake)
    |> Keyword.fetch!(key)
  end
end
