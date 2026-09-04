defmodule MeaningGame.Keeper.PrecedentTest do
  use MeaningGame.DataCase, async: false

  alias MeaningGame.Keeper.Precedent

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

    test "both orderings of anchors collapse to the same key" do
      forward = Precedent.key("gemini-3.8-flash", "assay-1", ["ocean", "night"], ["tide", "moon"])
      reverse = Precedent.key("gemini-3.8-flash", "assay-1", ["night", "ocean"], ["tide", "moon"])

      assert forward == reverse
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
  end
end
