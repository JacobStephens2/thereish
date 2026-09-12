defmodule Thereish.Steward.PrecedentTest do
  use Thereish.DataCase, async: false

  alias Thereish.Steward.Precedent

  describe "normalization" do
    test "downcases, trims, collapses whitespace, and applies NFC" do
      assert Precedent.normalize("  Beacon  ") == "beacon"
      assert Precedent.normalize("HIGH \t\n TIDE") == "high tide"
      # Decomposed cafe (e + combining acute accent) normalizes to composed NFC
      assert Precedent.normalize("cafe\u0301") == "café"
      assert Precedent.normalize("  Café  ") == "café"
    end
  end

  describe "cache key" do
    test "both orderings of bridges collapse to the same key" do
      forward = Precedent.key("gemini-3.8-flash", "assay-1", ["ocean", "night"], ["tide", "moon"])
      reverse = Precedent.key("gemini-3.8-flash", "assay-1", ["ocean", "night"], ["moon", "tide"])

      assert forward == reverse
    end

    test "both orderings of bookends collapse to the same key" do
      forward = Precedent.key("gemini-3.8-flash", "assay-1", ["ocean", "night"], ["tide", "moon"])
      reverse = Precedent.key("gemini-3.8-flash", "assay-1", ["night", "ocean"], ["tide", "moon"])

      assert forward == reverse
    end

    test "every ordering of an Attempt's four Bridges collapses to the same key" do
      roster =
        Precedent.key("gemini-3.8-flash", "assay-2", ["lantern", "harbour"], [
          "beacon",
          "cairn",
          "lamp",
          "seagull"
        ])

      # A table of four fills its Seats in whatever order four phones typed
      # their names, and the words they wrote are the same words either way.
      shuffled =
        Precedent.key("gemini-3.8-flash", "assay-2", ["lantern", "harbour"], [
          "lamp",
          "seagull",
          "beacon",
          "cairn"
        ])

      assert roster == shuffled
    end

    test "surface whitespace and casing do not fork a key" do
      base = Precedent.key("gemini-3.8-flash", "assay-1", ["ocean", "night"], ["tide", "moon"])

      messy =
        Precedent.key("gemini-3.8-flash", "assay-1", [" OCEAN ", "night\n"], [
          "  Tide  ",
          " MOON "
        ])

      assert base == messy
    end

    test "differing prompt versions produce different keys" do
      v1 = Precedent.key("gemini-3.8-flash", "assay-1", ["ocean", "night"], ["tide", "moon"])
      v2 = Precedent.key("gemini-3.8-flash", "assay-2", ["ocean", "night"], ["tide", "moon"])

      refute v1 == v2
    end

    test "differing models produce different keys" do
      m1 = Precedent.key("gemini-3.8-flash", "assay-1", ["ocean", "night"], ["tide", "moon"])
      m2 = Precedent.key("claude-fable", "assay-1", ["ocean", "night"], ["tide", "moon"])

      refute m1 == m2
    end

    test "a request with and without prior Quips hashes to the same key" do
      without = %{bookends: ["lantern", "harbour"], bridges: ["beacon", "cairn"]}

      with_quips =
        Map.put(without, :prior_quips, [
          "Jacob brought the lighthouse, Mara brought the dock."
        ])

      assert Precedent.key("gemini-3.8-flash", "assay-3", without) ==
               Precedent.key("gemini-3.8-flash", "assay-3", with_quips)
    end
  end

  describe "storing and fetching precedent" do
    @verdict %{
      closeness: 80,
      reasoning: "Both words name a marker left to be found.",
      quip: "One built it, the other lit it.",
      meta: %{
        model: "gemini-3.8-flash",
        prompt_version: "assay-1",
        cost_usd: 0.0018,
        forward: 85,
        reverse: 75,
        reasoning_reverse: "Both guide the lost."
      }
    }

    test "stores a verdict and retrieves it exactly as shown" do
      assert :miss =
               Precedent.get("gemini-3.8-flash", "assay-1", ["lantern", "harbour"], [
                 "beacon",
                 "cairn"
               ])

      assert {:ok, _precedent} =
               Precedent.put(
                 "gemini-3.8-flash",
                 "assay-1",
                 ["lantern", "harbour"],
                 ["beacon", "cairn"],
                 @verdict
               )

      assert {:ok, verdict} =
               Precedent.get("gemini-3.8-flash", "assay-1", ["lantern", "harbour"], [
                 "beacon",
                 "cairn"
               ])

      assert verdict.closeness == 80
      assert verdict.reasoning == "Both words name a marker left to be found."
      assert verdict.quip == "One built it, the other lit it."
      assert verdict.meta.model == "gemini-3.8-flash"
      assert verdict.meta.prompt_version == "assay-1"
      assert_in_delta verdict.meta.cost_usd, 0.0018, 0.00001
      assert verdict.meta.forward == 85
      assert verdict.meta.reverse == 75
      assert verdict.meta.reasoning_reverse == "Both guide the lost."
    end

    test "reverse ordering hits the same stored precedent" do
      Precedent.put(
        "gemini-3.8-flash",
        "assay-1",
        ["lantern", "harbour"],
        ["beacon", "cairn"],
        @verdict
      )

      assert {:ok, verdict} =
               Precedent.get("gemini-3.8-flash", "assay-1", ["harbour", "lantern"], [
                 "cairn",
                 "beacon"
               ])

      assert verdict.closeness == 80
      assert verdict.reasoning == @verdict.reasoning
    end

    test "nothing silently rewrites a stored precedent" do
      Precedent.put(
        "gemini-3.8-flash",
        "assay-1",
        ["lantern", "harbour"],
        ["beacon", "cairn"],
        @verdict
      )

      different_verdict = %{
        @verdict
        | closeness: 95,
          reasoning: "Actually they are identical.",
          quip: "Reconsidered."
      }

      # A later put for the same key must not overwrite the precedent
      assert {:ok, _} =
               Precedent.put(
                 "gemini-3.8-flash",
                 "assay-1",
                 ["lantern", "harbour"],
                 ["beacon", "cairn"],
                 different_verdict
               )

      assert {:ok, verdict} =
               Precedent.get("gemini-3.8-flash", "assay-1", ["lantern", "harbour"], [
                 "beacon",
                 "cairn"
               ])

      assert verdict.closeness == 80
      assert verdict.reasoning == "Both words name a marker left to be found."
      assert verdict.quip == "One built it, the other lit it."
    end

    test "a joint overrule rewrites stored precedent" do
      Precedent.put(
        "gemini-3.8-flash",
        "assay-1",
        ["lantern", "harbour"],
        ["beacon", "cairn"],
        @verdict
      )

      couple_ruling = %{
        closeness: 100,
        reasoning: "Overruled jointly across all Seats. Recorded as precedent.",
        quip: "House law."
      }

      assert {:ok, _} =
               Precedent.overrule(
                 "gemini-3.8-flash",
                 "assay-1",
                 ["lantern", "harbour"],
                 ["beacon", "cairn"],
                 couple_ruling
               )

      assert {:ok, verdict} =
               Precedent.get("gemini-3.8-flash", "assay-1", ["lantern", "harbour"], [
                 "beacon",
                 "cairn"
               ])

      assert verdict.closeness == 100
      assert verdict.reasoning == "Overruled jointly across all Seats. Recorded as precedent."
      assert verdict.quip == "House law."
    end
  end

  describe "the two words that landed furthest apart" do
    @table_verdict %{
      closeness: 27,
      reasoning: "Three of you were at the shore and one of you was not.",
      quip: "The seagull is having its own evening.",
      furthest: ["beacon", "seagull"],
      meta: %{
        model: "gemini-3.8-flash",
        prompt_version: "assay-2",
        cost_usd: 0.0021,
        forward: 30,
        reverse: 24,
        reasoning_reverse: "One word wandered."
      }
    }

    @table ["beacon", "cairn", "lamp", "seagull"]

    test "come back on a cache hit, so a stored Verdict can still be carried forward" do
      assert {:ok, _} =
               Precedent.put(
                 "gemini-3.8-flash",
                 "assay-2",
                 ["lantern", "harbour"],
                 @table,
                 @table_verdict
               )

      assert {:ok, verdict} =
               Precedent.get("gemini-3.8-flash", "assay-2", ["lantern", "harbour"], @table)

      # Without these two words a cache hit would replay the grade but not the
      # game: they are the next Attempt's Bookends (ADR-0010).
      assert verdict.furthest == ["beacon", "seagull"]
    end

    test "are stored as the players wrote them, not sorted like the key's inputs" do
      assert {:ok, _} =
               Precedent.put(
                 "gemini-3.8-flash",
                 "assay-2",
                 ["lantern", "harbour"],
                 @table,
                 %{@table_verdict | furthest: ["seagull", "Beacon"]}
               )

      assert {:ok, verdict} =
               Precedent.get("gemini-3.8-flash", "assay-2", ["lantern", "harbour"], @table)

      assert verdict.furthest == ["seagull", "Beacon"]
    end

    test "survive an overrule, because the players ruled on the grade and not on them" do
      Precedent.put(
        "gemini-3.8-flash",
        "assay-2",
        ["lantern", "harbour"],
        @table,
        @table_verdict
      )

      assert {:ok, _} =
               Precedent.overrule(
                 "gemini-3.8-flash",
                 "assay-2",
                 ["lantern", "harbour"],
                 @table,
                 %{closeness: 90, reasoning: "We all meant the same shore.", quip: "House law."}
               )

      assert {:ok, verdict} =
               Precedent.get("gemini-3.8-flash", "assay-2", ["lantern", "harbour"], @table)

      assert verdict.closeness == 90
      assert verdict.furthest == ["beacon", "seagull"]
    end

    test "are absent from a Verdict that never named any, and that is not an error" do
      assert {:ok, _} =
               Precedent.put(
                 "gemini-3.8-flash",
                 "assay-2",
                 ["lantern", "harbour"],
                 ["beacon", "cairn"],
                 Map.delete(@table_verdict, :furthest)
               )

      assert {:ok, verdict} =
               Precedent.get("gemini-3.8-flash", "assay-2", ["lantern", "harbour"], [
                 "beacon",
                 "cairn"
               ])

      assert verdict.furthest == nil
    end

    test "accepts request maps directly for key, get, put, and overrule" do
      req = %{bookends: ["ocean", "night"], bridges: ["tide", "moon"]}

      assert Precedent.key("gemini-3.8-flash", "assay-1", req) ==
               Precedent.key("gemini-3.8-flash", "assay-1", req.bookends, req.bridges)

      assert Precedent.get("gemini-3.8-flash", "assay-1", req) == :miss

      assert {:ok, _} = Precedent.put("gemini-3.8-flash", "assay-1", req, @verdict)
      assert {:ok, verdict} = Precedent.get("gemini-3.8-flash", "assay-1", req)
      assert verdict.closeness == @verdict.closeness

      assert {:ok, _} =
               Precedent.overrule("gemini-3.8-flash", "assay-1", req, %{
                 closeness: 99,
                 reasoning: "Overruled via request map."
               })

      assert {:ok, overruled} = Precedent.get("gemini-3.8-flash", "assay-1", req)
      assert overruled.closeness == 99
    end

    test "the version bump to assay-3 orphans assay-2 precedents" do
      req = %{bookends: ["ocean", "night"], bridges: ["tide", "moon"]}

      {:ok, _} =
        Precedent.put("gemini-3.8-flash", "assay-2", req, %{
          closeness: 85,
          reasoning: "Old assay-2 verdict.",
          quip: "Old quip.",
          meta: %{model: "gemini-3.8-flash", prompt_version: "assay-2"}
        })

      assert Precedent.get("gemini-3.8-flash", "assay-3", req) == :miss
    end

    test "the version bump to assay-4 orphans assay-3 precedents" do
      req = %{bookends: ["ocean", "night"], bridges: ["tide", "moon"]}

      {:ok, _} =
        Precedent.put("gemini-3.8-flash", "assay-3", req, %{
          closeness: 85,
          reasoning: "Old assay-3 verdict.",
          quip: "Old quip.",
          meta: %{model: "gemini-3.8-flash", prompt_version: "assay-3"}
        })

      assert Precedent.get("gemini-3.8-flash", "assay-4", req) == :miss
    end

    test "every ordering of N Bookends and N Bridges collapses to the same key" do
      roster =
        Precedent.key(
          "gemini-3.8-flash",
          "assay-4",
          ["lantern", "harbour", "wharf", "dusk"],
          ["beacon", "cairn", "lamp", "seagull"]
        )

      shuffled =
        Precedent.key(
          "gemini-3.8-flash",
          "assay-4",
          ["dusk", "wharf", "lantern", "harbour"],
          ["lamp", "seagull", "beacon", "cairn"]
        )

      assert roster == shuffled
    end
  end
end
