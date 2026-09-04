defmodule MeaningGame.Keeper.Fake do
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

      config :meaning_game, :keeper, fake: [delay_ms: 0, mode: :grade]

  `delay_ms` is how long a verdict takes. `mode: :unavailable` is an Assayer
  that says it cannot answer, and `mode: :raise` is one that falls over without
  saying anything — the two shapes a failed grade comes in, both of which the
  game answers the same way.
  """
  @behaviour MeaningGame.Keeper

  @impl true
  def assay(%{anchors: [_, _], bridges: [left, right]}) do
    delay_ms() |> Process.sleep()

    case mode() do
      :grade -> {:ok, grade(left, right)}
      :unavailable -> {:error, :no_verdict}
      :raise -> raise "this Assayer is having a moment"
    end
  end

  defp grade(left, right) do
    shared = shared_prefix(left, right)

    %{
      closeness: round(200 * shared / (String.length(left) + String.length(right))),
      reasoning:
        "\"#{left}\" and \"#{right}\" share #{shared} letters from the front. " <>
          "That is all this Assayer knows how to look at.",
      # Provenance the Chronicle wants from every grader, answered honestly by
      # the one that has no model behind it and costs nothing to run.
      meta: %{model: "fake", prompt_version: "fake-1", cost_usd: 0.0}
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
    |> Application.fetch_env!(:keeper)
    |> Keyword.fetch!(:fake)
    |> Keyword.fetch!(key)
  end
end
