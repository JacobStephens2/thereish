defmodule Thereish.StewardSmokeTest do
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

      GEMINI_API_KEY=... ANTHROPIC_API_KEY=... OPENAI_API_KEY=... mix test --include live

  One test per role, and one more for the table: the couch's grading and a
  four-word grading are the same call, but they are not the same prompt or the
  same judgement, and the reveal beat is the same beat at four Seats as at two
  (ADR-0010).
  """
  use Thereish.DataCase, async: false

  @moduletag :live

  import Thereish.StewardFixtures

  alias Thereish.Ladder
  alias Thereish.Steward

  setup context do
    cond do
      context[:eleven_labs] -> let_it_call_eleven_labs()
      context[:hume] -> let_it_call_hume()
      context[:anthropic] -> let_it_call_anthropic()
      context[:openai] -> let_it_call_openai()
      true -> let_it_call_the_provider()
    end
  end

  test "the Assayer grades a real pair, in both orderings, inside the beat" do
    {:ok, verdict} =
      Steward.assay(%{bookends: ["ocean", "night"], bridges: ["tide", "moon"]})

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
    # p95 — `Thereish.Steward.Latency` is — but a single round trip over that
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
      Steward.assay(%{bookends: ["harbour", "dusk"], bridges: bridges})

    assert verdict.closeness in 0..100
    assert Ladder.read(verdict.closeness).band != nil

    # Three words at the shore's light and one bird. It reads as a set that
    # mostly converged rather than as a miss, which is the whole reason the
    # prompt was rewritten.
    assert verdict.closeness >= 40

    assert String.trim(verdict.reasoning) != ""
    assert String.trim(verdict.quip) != ""

    # The carry-forward is two words somebody actually wrote, because those two
    # are about to be the next Attempt's Bookends. That they are two *different*
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

  test "the Assayer grades a real table against N Bookends, and names two of their words" do
    bookends = ["harbour", "dusk", "lantern", "wharf"]
    bridges = ["lighthouse", "beacon", "lamp", "gull"]

    {:ok, verdict} = Steward.assay(%{bookends: bookends, bridges: bridges})

    assert verdict.closeness in 0..100
    assert Ladder.read(verdict.closeness).band != nil
    assert String.trim(verdict.reasoning) != ""
    assert String.trim(verdict.quip) != ""
    assert verdict.meta.prompt_version == Thereish.Steward.Assay.version()

    assert [left, right] = verdict.furthest
    assert left in bridges
    assert right in bridges
    assert verdict.meta.latency_ms < 4_000

    IO.puts(
      "\n  live Assayer at four Bookends: #{verdict.closeness} " <>
        "(#{verdict.meta.forward}/#{verdict.meta.reverse}) " <>
        "in #{verdict.meta.latency_ms} ms for $#{Float.round(verdict.meta.cost_usd, 5)}" <>
        "\n  furthest apart: #{left} / #{right}" <>
        "\n  #{verdict.reasoning}\n  #{verdict.quip}\n"
    )
  end

  test "the Author writes Bookends from two real Gives inside the deadline" do
    gives = [
      %{name: "Mara", text: "candlelit cathedral"},
      %{name: "Jacob", text: "cyberpunk nightclub"}
    ]

    {:ok, answer} = Steward.author(%{gives: gives})

    assert [left, right] = answer.bookends
    assert is_binary(left) and byte_size(left) > 0
    assert is_binary(right) and byte_size(right) > 0
    assert String.trim(answer.why) != ""

    assert answer.meta.model =~ "gemini"
    assert answer.meta.cost_usd > 0
    assert answer.meta.latency_ms < 8_000

    IO.puts(
      "\n  live Author: #{left} / #{right} in #{answer.meta.latency_ms} ms " <>
        "for $#{Float.round(answer.meta.cost_usd, 5)}" <>
        "\n  why: #{answer.why}\n"
    )
  end

  @tag :openai
  test "the Author writes Bookends using OpenAI Astra (gpt-6-astra) inside the deadline" do
    gives = [
      %{name: "Mara", text: "candlelit cathedral"},
      %{name: "Jacob", text: "cyberpunk nightclub"}
    ]

    {:ok, answer} = Steward.author(%{gives: gives}, job: :astra)

    assert [left, right] = answer.bookends
    assert is_binary(left) and byte_size(left) > 0
    assert is_binary(right) and byte_size(right) > 0
    assert String.trim(answer.why) != ""

    assert answer.meta.model =~ "gpt-6-astra"
    assert answer.meta.arm == :astra
    assert answer.meta.cost_usd > 0
    assert answer.meta.latency_ms < 10_000

    IO.puts(
      "\n  live Author (Astra): #{left} / #{right} in #{answer.meta.latency_ms} ms " <>
        "for $#{Float.round(answer.meta.cost_usd, 5)}" <>
        "\n  why: #{answer.why}\n"
    )
  end

  @tag :anthropic
  test "the Scribe writes a real recap, and Vale lets it through" do
    page = %{
      bookends: ["lantern", "harbour"],
      melded: true,
      attempts: [
        %{
          number: 1,
          bookends: ["lantern", "harbour"],
          bridges: [
            %{seat_name: "Jacob", bridge: "keeper"},
            %{seat_name: "Mara", bridge: "guide"}
          ],
          verdicts: [
            %{band: "adjacent", reasoning: "Two jobs on the same shore.", closeness: 41}
          ]
        },
        %{
          number: 2,
          bookends: ["keeper", "guide"],
          bridges: [
            %{seat_name: "Jacob", bridge: "watch"},
            %{seat_name: "Mara", bridge: "watch"}
          ],
          verdicts: [%{band: "deep_meld", reasoning: "The same word twice.", closeness: 100}]
        }
      ]
    }

    digest = """
    Page 1 (candy · cane) [Give: Christmas] — Melded on attempt 2 (closeness: 88, meld)
      Attempt 2: Jacob bridged "hook", Mara bridged "hook". Verdict: 88 (meld)
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

  @tag :eleven_labs
  test "ElevenLabs v3 Conversational speaks a real line" do
    line = "Miss. A quiet night at the harbour."
    {:ok, result} = Steward.speak(line, provider: Thereish.Steward.ElevenLabs)

    assert result.format == :mp3
    assert is_binary(result.audio)
    assert byte_size(result.audio) > 1000
    assert result.meta.provider == Thereish.Steward.ElevenLabs
    assert result.meta.characters > 0
    assert result.meta.cost_usd > 0
  end

  @tag :hume
  test "Hume Octave 2 speaks a real line" do
    line = "Meld. Two minds at once."
    {:ok, result} = Steward.speak(line, provider: Thereish.Steward.Hume)

    assert result.format == :mp3
    assert is_binary(result.audio)
    assert byte_size(result.audio) > 1000
    assert result.meta.provider == Thereish.Steward.Hume
    assert result.meta.characters > 0
    assert result.meta.cost_usd > 0
  end

  test "the Scribe names a Room from a real digest once by hand" do
    alias Thereish.Steward.Legality

    digest = """
    Page 1 (candy · cane) — Melded on attempt 2 (closeness: 88, meld)
      Attempt 2: Jacob bridged "hook", Mara bridged "hook". Verdict: 88 (meld)
    """

    taken = ["couch", "flak"]

    {:ok, %{word: code}} = Steward.name_room([digest], taken)

    assert is_binary(code)
    assert String.length(code) == 4
    assert Legality.in_dictionary?(code)
    refute Legality.profane?(code)
    refute code in taken

    IO.puts("\n  live Scribe named Room: #{String.upcase(code)}\n")
  end
end
