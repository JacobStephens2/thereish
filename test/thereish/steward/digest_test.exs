defmodule Thereish.Steward.DigestTest do
  @moduledoc """
  What each Steward role reads of the Chronicle, composed from Page views built
  in memory. No database: whether a Page reads this way once written is the
  Chronicle's test; what a role is allowed to read of it is this one.
  """
  use ExUnit.Case, async: true

  alias Thereish.Steward.Digest

  defp verdict(attrs) do
    Map.merge(
      %{
        bridges: ["cairn", "cairns"],
        closeness: 91,
        band: "meld",
        reasoning: "Both are stacked stones on a hill."
      },
      Map.new(attrs)
    )
  end

  defp view(attrs \\ []) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        bookends: ["lantern", "harbour"],
        gives: [],
        melded: true,
        closeness: 91,
        attempts: [
          %{
            number: 1,
            bridges: [
              %{seat_name: "Mara", bridge: "cairn"},
              %{seat_name: "Jacob", bridge: "cairns"}
            ],
            verdicts: [verdict([])]
          }
        ],
        overrules: [],
        corrections: [],
        recap: nil
      },
      Map.new(attrs)
    )
  end

  defp overrule(attrs \\ []) do
    Map.merge(
      %{proposer_name: "Mara", couple_closeness: 88, couple_reasoning: "Water in the desert."},
      Map.new(attrs)
    )
  end

  defp recap do
    %{recap: "They found cairn on the first try.", callback: "Cairn again, like last month."}
  end

  describe "the Author's digest" do
    test "is the first-Page message for a Room with no Pages" do
      assert Digest.author([]) == "Nothing yet; this is the first Page."
    end

    test "reads each Page with its outcome, Bridges and Verdict" do
      digest = Digest.author([view()])

      assert digest =~ "Page 1 (lantern · harbour)"
      assert digest =~ "Melded on attempt 1 (closeness: 91, meld)"
      assert digest =~ ~s(Mara bridged "cairn")
      assert digest =~ ~s(Jacob bridged "cairns")
      assert digest =~ "Verdict: 91 (meld) — Both are stacked stones on a hill."
    end

    test "reads word for word as it always has" do
      views = [
        view(
          gives: [%{seat_name: "Mara", text: "nurse"}, %{seat_name: "Jacob", text: "clinic"}],
          overrules: [overrule()],
          corrections: [
            %{
              author_name: "Jacob",
              target: "bridge",
              original_value: "cairns",
              corrected_value: "cairn",
              note: "typo"
            }
          ]
        ),
        view(
          bookends: ["candy", "cane"],
          melded: false,
          closeness: nil,
          gives: [%{seat_name: nil, text: "winter"}],
          attempts: [
            %{
              number: 1,
              bridges: [%{seat_name: "Mara", bridge: "stripe"}],
              verdicts: []
            },
            %{
              number: 2,
              bridges: [%{seat_name: "Mara", bridge: "mint"}],
              verdicts: [
                verdict(bridges: ["mint", "sugar"], closeness: 40, band: "far", reasoning: nil),
                verdict(bridges: ["mint", "peppermint"], closeness: 70, band: nil)
              ]
            }
          ]
        )
      ]

      assert Digest.author(views) ==
               """
               Page 1 (lantern · harbour) [Give (Mara): nurse, Give (Jacob): clinic] — Melded on attempt 1 (closeness: 91, meld)
                 Attempt 1: Mara bridged "cairn", Jacob bridged "cairns". Verdict: 91 (meld) — Both are stacked stones on a hill.
                 Overruled: Mara proposed overrule to 88 ("Water in the desert.")
                 Correction by Jacob: corrected bridge from "cairns" to "cairn" ("typo")

               Page 2 (candy · cane) [Give: winter] — Unmelded after 2 attempts
                 Attempt 1: Mara bridged "stripe". Verdict: Ungraded
                 Attempt 2: Mara bridged "mint".
                   Pair [mint / sugar]: 40 (far)
                   Pair [mint / peppermint]: 70 — Both are stacked stones on a hill.\
               """
    end

    test "names every Give at a Full table" do
      gives = [%{seat_name: "Mara", text: "nurse"}, %{seat_name: "Jacob", text: "clinic"}]

      assert Digest.author([view(gives: gives)]) =~
               "[Give (Mara): nurse, Give (Jacob): clinic]"
    end

    test "leaves the Scribe's recaps and callbacks out" do
      digest = Digest.author([view(recap: recap())])

      refute digest =~ recap().recap
      refute digest =~ recap().callback
    end
  end

  describe "the Scribe's digest" do
    test "reads a Verdict with no band as graded, and no number" do
      attempt = %{
        number: 1,
        bridges: [%{seat_name: "Mara", bridge: "cairn"}],
        verdicts: [verdict(band: nil, reasoning: nil)]
      }

      digest = Digest.scribe([view(attempts: [attempt])])

      assert digest ==
               """
               Page 1 (lantern · harbour) — Melded on attempt 1
                 Attempt 1: Mara bridged "cairn". Verdict: graded\
               """
    end

    test "is the first-Page message for a Room with no Pages" do
      assert Digest.scribe([]) == "Nothing yet; this is the first Page."
    end

    test "folds in the recaps and callbacks already written" do
      digest = Digest.scribe([view(recap: recap())])

      assert digest =~ "  Recap: #{recap().recap}"
      assert digest =~ "  Callback: #{recap().callback}"
    end

    test "carries no grade, and keeps the bands, reasoning, Bridges and Gives" do
      legacy_attempt = %{
        number: 2,
        bridges: [%{seat_name: "Mara", bridge: "mint"}],
        verdicts: [
          verdict(bridges: ["mint", "sugar"], closeness: 91, band: "far"),
          verdict(bridges: ["mint", "peppermint"], closeness: 91)
        ]
      }

      page =
        view(
          gives: [%{seat_name: "Mara", text: "nurse"}],
          attempts: [legacy_attempt | view().attempts] |> Enum.reverse(),
          overrules: [overrule()]
        )

      digest = Digest.scribe([page])

      refute digest =~ "91"
      refute digest =~ "88"
      refute digest =~ "closeness"

      assert digest =~ "Melded on attempt 2 (far)"
      assert digest =~ "Verdict: meld — Both are stacked stones on a hill."
      assert digest =~ "Pair [mint / sugar]: far — Both are stacked stones on a hill."
      assert digest =~ ~s{Overruled: Mara proposed an overrule ("Water in the desert.")}
      assert digest =~ ~s(Mara bridged "cairn")
      assert digest =~ "[Give (Mara): nurse]"
    end
  end

  describe "the Assayer's digest" do
    defp quipped(quips) do
      view(
        attempts:
          Enum.with_index(quips, 1)
          |> Enum.map(fn {quip, number} ->
            %{number: number, bridges: [], verdicts: [verdict(quip: quip)]}
          end)
      )
    end

    defp request(quips) do
      %{
        bookends: ["lantern", "harbour"],
        bridges: ["cairn", "cairo"],
        earlier_attempts:
          Enum.with_index(quips, 1)
          |> Enum.map(fn {quip, number} ->
            %{number: number, bookends: ["lantern", "harbour"], bridges: [], quip: quip}
          end)
      }
    end

    test "is no Quips for a Room with no Pages and a first Attempt" do
      assert Digest.assayer([], request([])) == []
    end

    test "reads the Chronicle's Quips in play order, then this Page's" do
      views = [quipped(["first", "second"]), quipped(["third"])]

      assert Digest.assayer(views, request(["fourth"])) == ["first", "second", "third", "fourth"]
    end

    test "keeps only the last five" do
      views = [quipped(["one", "two", "three"]), quipped(["four", "five"])]

      assert Digest.assayer(views, request(["six"])) == ["two", "three", "four", "five", "six"]
    end

    test "drops blank and missing Quips" do
      views = [quipped(["kept", "", nil])]

      assert Digest.assayer(views, request([nil, "", "also kept"])) == ["kept", "also kept"]
    end

    test "reads every verdict's Quip on an Attempt written before ADR-0010" do
      legacy =
        view(
          attempts: [
            %{
              number: 1,
              bridges: [],
              verdicts: [verdict(quip: "first pair"), verdict(quip: "second pair")]
            }
          ]
        )

      assert Digest.assayer([legacy], request([])) == ["first pair", "second pair"]
    end

    test "reads a request without earlier Attempts as a first Attempt" do
      assert Digest.assayer([quipped(["only"])], %{bookends: [], bridges: []}) == ["only"]
    end
  end
end
