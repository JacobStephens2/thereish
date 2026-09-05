defmodule MeaningGame.StewardSmokeTest do
  @moduledoc """
  The one test that actually calls a provider.

  Recorded responses prove that the Steward does the right thing with an answer.
  Only this proves that the answer still comes back — that the model id is still
  served, that the schema is still honoured, that the key in the environment
  works, and that the whole round trip fits inside a reveal. It is excluded from
  the default run (`test/test_helper.exs`) because a suite that spends money or
  depends on somebody's uptime is a suite nobody runs.

  Run it by hand, with a key, after changing anything about the prompt, the
  schema, or the model:

      GEMINI_API_KEY=... ANTHROPIC_API_KEY=... mix test --include live

  One test per role, and one more for the table: the couch's grading and a
  four-word grading are the same call, but they are not the same prompt or the
  same judgement, and the reveal beat is the same beat at four Seats as at two
  (ADR-0010).
  """
  use ExUnit.Case, async: false

  @moduletag :live

  import MeaningGame.StewardFixtures

  alias MeaningGame.Ladder
  alias MeaningGame.Steward

  setup context do
    if context[:anthropic], do: let_it_call_anthropic(), else: let_it_call_the_provider()
  end

  test "the Assayer grades a real pair, in both orderings, inside the beat" do
    {:ok, verdict} =
      Steward.assay(%{anchors: ["ocean", "night"], bridges: ["tide", "moon"]})

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
    # p95 — `MeaningGame.Steward.Latency` is — but a single round trip over that
    # is a result on its own.
    assert verdict.meta.latency_ms < 4_000

    IO.puts(
      "\n  live Assayer: #{verdict.closeness} " <>
        "(#{verdict.meta.forward}/#{verdict.meta.reverse}) " <>
        "in #{verdict.meta.latency_ms} ms for $#{Float.round(verdict.meta.cost_usd, 5)}" <>
        "\n  #{verdict.reasoning}\n  #{verdict.quip}\n"
    )
  end

  test "the Assayer grades a real table of four, and names two of their words" do
    bridges = ["lighthouse", "beacon", "lamp", "gull"]

    {:ok, verdict} =
      Steward.assay(%{anchors: ["harbour", "dusk"], bridges: bridges})

    assert verdict.closeness in 0..100
    assert Ladder.read(verdict.closeness).band != nil

    # Three words at the shore's light and one bird. It reads as a set that
    # mostly converged rather than as a miss, which is the whole reason the
    # prompt was rewritten.
    assert verdict.closeness >= 40

    assert String.trim(verdict.reasoning) != ""
    assert String.trim(verdict.quip) != ""

    # The carry-forward is two words somebody actually wrote, because those two
    # are about to be the next Attempt's Anchors. That they are two *different*
    # words is not asserted and not enforced: a table that all wrote "moon" has
    # "moon" and "moon" as its furthest pair, and nothing defends against the two
    # carried words being the same word.
    assert [left, right] = verdict.furthest
    assert left in bridges
    assert right in bridges

    assert verdict.meta.latency_ms < 4_000

    IO.puts(
      "\n  live Assayer at four: #{verdict.closeness} " <>
        "(#{verdict.meta.forward}/#{verdict.meta.reverse}) " <>
        "in #{verdict.meta.latency_ms} ms for $#{Float.round(verdict.meta.cost_usd, 5)}" <>
        "\n  furthest apart: #{left} / #{right}" <>
        "\n  #{verdict.reasoning}\n  #{verdict.quip}\n"
    )
  end

  @tag :anthropic
  test "the Scribe writes a real recap, and Vale lets it through" do
    page = %{
      anchors: ["lantern", "harbour"],
      melded: true,
      attempts: [
        %{
          number: 1,
          anchors: ["lantern", "harbour"],
          bridges: [
            %{seat_name: "Jacob", bridge: "keeper"},
            %{seat_name: "Melissa", bridge: "guide"}
          ],
          verdicts: [
            %{band: "adjacent", reasoning: "Two jobs on the same shore.", closeness: 41}
          ]
        },
        %{
          number: 2,
          anchors: ["keeper", "guide"],
          bridges: [
            %{seat_name: "Jacob", bridge: "watch"},
            %{seat_name: "Melissa", bridge: "watch"}
          ],
          verdicts: [%{band: "deep_meld", reasoning: "The same word twice.", closeness: 100}]
        }
      ]
    }

    digest = """
    Page 1 (candy · cane) [Give: Christmas] — Melded on attempt 2 (closeness: 88, meld)
      Attempt 2: Jacob bridged "hook", Melissa bridged "hook". Verdict: 88 (meld)
      Recap: Both of them wrote hook, and neither would say why.
    """

    {:ok, recap} = Steward.recap(page, digest)

    # It got past both gates, which is the whole claim: a real model's real
    # paragraph is prose the couch would be shown.
    assert String.trim(recap.recap) != ""
    refute recap.recap =~ ~r/\d/

    # A digest with a candy cane in it is a digest with something to reach back
    # for, though whether the Scribe reaches is its own judgement rather than
    # something to fail a build over.
    IO.puts(
      "\n  live Scribe: #{recap.meta.model} in #{recap.meta.latency_ms} ms " <>
        "over #{recap.meta.attempts} attempt(s) for $#{Float.round(recap.meta.cost_usd, 5)}" <>
        "\n  #{recap.recap}" <>
        "\n  callback: #{recap.callback || "(none)"}\n"
    )
  end
end
