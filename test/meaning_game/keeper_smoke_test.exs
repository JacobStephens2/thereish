defmodule MeaningGame.KeeperSmokeTest do
  @moduledoc """
  The one test that actually calls a provider.

  Recorded responses prove that the Keeper does the right thing with an answer.
  Only this proves that the answer still comes back — that the model id is still
  served, that the schema is still honoured, that the key in the environment
  works, and that the whole round trip fits inside a reveal. It is excluded from
  the default run (`test/test_helper.exs`) because a suite that spends money or
  depends on somebody's uptime is a suite nobody runs.

  Run it by hand, with a key, after changing anything about the prompt, the
  schema, or the model:

      GEMINI_API_KEY=... mix test --include live

  One test per role. There is one role.
  """
  use ExUnit.Case, async: false

  @moduletag :live

  import MeaningGame.KeeperFixtures

  alias MeaningGame.Keeper
  alias MeaningGame.Ladder

  setup do
    let_it_call_the_provider()
  end

  test "the Assayer grades a real pair, in both orderings, inside the beat" do
    {:ok, verdict} =
      Keeper.assay(%{anchors: ["ocean", "night"], bridges: ["tide", "moon"]})

    assert verdict.closeness in 0..100
    assert Ladder.read(verdict.closeness).band != nil

    # It quips on what the players actually wrote, and argues for its grade.
    assert String.trim(verdict.reasoning) != ""
    assert String.trim(verdict.quip) != ""

    # Both orderings were asked, and the grade is what they came to together.
    assert verdict.meta.forward in 0..100
    assert verdict.meta.reverse in 0..100
    assert verdict.meta.model =~ "gemini"
    assert verdict.meta.cost_usd > 0

    # The p95 target the reveal has to absorb is four seconds. One call is not a
    # p95 — `MeaningGame.Keeper.Latency` is — but a single round trip over that
    # is a result on its own.
    assert verdict.meta.latency_ms < 4_000

    IO.puts(
      "\n  live Assayer: #{verdict.closeness} " <>
        "(#{verdict.meta.forward}/#{verdict.meta.reverse}) " <>
        "in #{verdict.meta.latency_ms} ms for $#{Float.round(verdict.meta.cost_usd, 5)}" <>
        "\n  #{verdict.reasoning}\n  #{verdict.quip}\n"
    )
  end
end
