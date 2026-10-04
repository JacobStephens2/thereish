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
              %{seat_name: "Melissa", bridge: "cairn"},
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
      %{proposer_name: "Melissa", couple_closeness: 88, couple_reasoning: "Water in the desert."},
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
      assert digest =~ ~s(Melissa bridged "cairn")
      assert digest =~ ~s(Jacob bridged "cairns")
      assert digest =~ "Verdict: 91 (meld) — Both are stacked stones on a hill."
    end

    test "reads word for word as it always has" do
      views = [
        view(
          gives: [%{seat_name: "Melissa", text: "nurse"}, %{seat_name: "Jacob", text: "clinic"}],
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
              bridges: [%{seat_name: "Melissa", bridge: "stripe"}],
              verdicts: []
            },
            %{
              number: 2,
              bridges: [%{seat_name: "Melissa", bridge: "mint"}],
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
               Page 1 (lantern · harbour) [Give (Melissa): nurse, Give (Jacob): clinic] — Melded on attempt 1 (closeness: 91, meld)
                 Attempt 1: Melissa bridged "cairn", Jacob bridged "cairns". Verdict: 91 (meld) — Both are stacked stones on a hill.
                 Overruled: Melissa proposed overrule to 88 ("Water in the desert.")
                 Correction by Jacob: corrected bridge from "cairns" to "cairn" ("typo")

               Page 2 (candy · cane) [Give: winter] — Unmelded after 2 attempts
                 Attempt 1: Melissa bridged "stripe". Verdict: Ungraded
                 Attempt 2: Melissa bridged "mint".
                   Pair [mint / sugar]: 40 (far)
                   Pair [mint / peppermint]: 70 — Both are stacked stones on a hill.\
               """
    end

    test "names every Give at a Full table" do
      gives = [%{seat_name: "Melissa", text: "nurse"}, %{seat_name: "Jacob", text: "clinic"}]

      assert Digest.author([view(gives: gives)]) =~
               "[Give (Melissa): nurse, Give (Jacob): clinic]"
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
        bridges: [%{seat_name: "Melissa", bridge: "cairn"}],
        verdicts: [verdict(band: nil, reasoning: nil)]
      }

      digest = Digest.scribe([view(attempts: [attempt])])

      assert digest ==
               """
               Page 1 (lantern · harbour) — Melded on attempt 1
                 Attempt 1: Melissa bridged "cairn". Verdict: graded\
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
        bridges: [%{seat_name: "Melissa", bridge: "mint"}],
        verdicts: [
          verdict(bridges: ["mint", "sugar"], closeness: 91, band: "far"),
          verdict(bridges: ["mint", "peppermint"], closeness: 91)
        ]
      }

      page =
        view(
          gives: [%{seat_name: "Melissa", text: "nurse"}],
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
      assert digest =~ ~s{Overruled: Melissa proposed an overrule ("Water in the desert.")}
      assert digest =~ ~s(Melissa bridged "cairn")
      assert digest =~ "[Give (Melissa): nurse]"
    end
  end
end
