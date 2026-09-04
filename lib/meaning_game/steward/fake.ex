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

  Two knobs, both configuration, both for the tests that need the Room to be
  waiting on something:

      config :meaning_game, :steward, fake: [delay_ms: 0, mode: :grade]

  `delay_ms` is how long a verdict takes. `mode: :unavailable` is an Assayer
  that says it cannot answer, and `mode: :raise` is one that falls over without
  saying anything — the two shapes a failed grade comes in, both of which the
  game answers the same way.
  """
  @behaviour MeaningGame.Steward

  @impl true
  def assay(%{anchors: [_, _], bridges: [left, right]}) do
    delay_ms() |> Process.sleep()

    case mode() do
      :grade -> {:ok, grade(left, right)}
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
        %{anchors: anchors, bait: bait, deep_bridges: deep_bridges} = authored_bridges(give)
        likely_bridges = [bait | deep_bridges] ++ ["prayer", "faith"]

        json = %{
          "theme" => give || chapter,
          "anchors" => anchors,
          "bait" => bait,
          "deep_bridges" => deep_bridges,
          "likely_bridges" => likely_bridges,
          "why_these" => "The anchors invite #{bait} as the immediate trap.",
          "band_scripts" => %{
            "miss" => "Different neighbourhoods entirely.",
            "adjacent" => "On the same block, across the street.",
            "near" => "In the same backyard.",
            "meld" => "You both saw the grill.",
            "deep_meld" => "Two minds at the mower."
          }
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

  defp authored_bridges(nil) do
    %{
      anchors: ["backyard", "weekend"],
      bait: "barbecue",
      deep_bridges: ["lawnmower", "chores"]
    }
  end

  defp authored_bridges(give) do
    %{
      anchors: give_anchors(give),
      bait: "altar",
      deep_bridges: ["saint", "church"]
    }
  end

  defp give_anchors("hospital" <> _), do: ["nurse", "clinic"]
  defp give_anchors(_give), do: ["candle", "chapel"]

  defp author_delay_ms, do: config_get(:author_delay_ms, 0)
  defp author_mode, do: config_get(:author_mode, :ok)

  defp config_get(key, default) do
    :meaning_game
    |> Application.get_env(:steward, [])
    |> Keyword.get(:fake, [])
    |> Keyword.get(key, default)
  end

  defp grade(left, right) do
    shared = shared_prefix(left, right)
    closeness = round(200 * shared / (String.length(left) + String.length(right)))

    %{
      closeness: closeness,
      reasoning:
        "\"#{left}\" and \"#{right}\" share #{shared} letters from the front. " <>
          "That is all this Assayer knows how to look at.",
      # Named after the players' actual Bridges, like the live one's, so that
      # every screen the quip is drawn on is exercised by a test that never
      # calls anybody (ADR-0005).
      quip: "\"#{left}\" and \"#{right}\" walk into a bar. The bar has no opinion.",
      # Provenance the Chronicle wants from every Assayer, answered honestly by
      # the one that has no model behind it and costs nothing to run. Both
      # orderings agree because this Assayer is a symmetric function of two
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
