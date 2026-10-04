defmodule Thereish.Chronicle.MarkdownTest do
  @moduledoc """
  The Markdown export, rendered from Page views built in memory and parsed back.
  No database: whether the Chronicle reads the right rows is the Chronicle's
  test; how those rows read as Markdown, in both directions, is this one.
  """
  use ExUnit.Case, async: true

  alias Thereish.Chronicle.Markdown
  alias Thereish.Chronicle.PageView
  alias Thereish.Chronicle.Spend
  alias Thereish.Foley.Vamp

  @spend Spend.tally([])

  defp render(pages), do: Markdown.render("dust", pages, @spend)

  defp round_trip(pages) do
    assert {:ok, parsed} = pages |> render() |> Markdown.parse()
    parsed
  end

  defp page(attrs \\ []) do
    struct!(
      %PageView{
        id: "page",
        room_id: "room",
        bookends: ["lantern", "harbour"],
        closed_because: "attempts_spent",
        melded: false,
        closeness: 27,
        opened_at: ~U[2026-10-03 20:00:00.000000Z],
        closed_at: ~U[2026-10-03 20:05:00.000000Z],
        experiment_unblinded: false,
        attempts: [attempt(1)]
      },
      attrs
    )
  end

  defp attempt(number, attrs \\ []) do
    Map.merge(
      %{
        id: "attempt-#{number}",
        number: number,
        bookends: ["lantern", "harbour"],
        closeness: 27,
        melded: false,
        bridges: [bridge("Melissa", "beacon"), bridge("Jacob", "cairn")],
        participant_ids: [],
        verdicts: [verdict()],
        carried: nil,
        bookend_chips: [],
        overrules: [],
        corrections: [],
        fairness_taps: []
      },
      Map.new(attrs)
    )
  end

  defp bridge(seat_name, word), do: %{seat_name: seat_name, bridge: word}

  defp verdict(attrs \\ []) do
    Map.merge(
      %{
        bridges: ["beacon", "cairn"],
        closeness: 27,
        band: "miss",
        reasoning: "One went to sea, one stayed ashore.",
        quip: "Ships passing in the fog.",
        model: nil,
        prompt_version: nil,
        latency_ms: nil,
        cost_usd: nil
      },
      Map.new(attrs)
    )
  end

  defp correction(attrs) do
    Map.merge(
      %{
        author_name: "Jacob",
        attempt_number: nil,
        target: "recap",
        original_value: nil,
        corrected_value: "We found the lighthouse.",
        note: nil
      },
      Map.new(attrs)
    )
  end

  describe "a round trip keeps each Seat's Bridge" do
    for name <- ["Quip", "Model", "Closeness", "By Ann", "Bookend Betty", "Bo: Me"] do
      test "when a Seat is named #{inspect(name)}" do
        bridges = [bridge(unquote(name), "cairn"), bridge("Jacob", "beacon")]
        [parsed] = round_trip([page(attempts: [attempt(1, bridges: bridges)])])

        assert [attempt] = parsed.attempts
        assert attempt.bridges == [{unquote(name), "cairn"}, {"Jacob", "beacon"}]
        assert attempt.quip == "Ships passing in the fog."
        assert attempt.reasoning == "One went to sea, one stayed ashore."
        assert attempt.closeness == 27
        assert attempt.band == "miss"
      end
    end
  end

  describe "a round trip of a Page written before ADR-0010" do
    test "reads its pair Verdicts as no extra Bridges" do
      verdicts = [
        verdict(bridges: ["cairn", "beacon"], closeness: 40, quip: "Close-ish."),
        verdict(bridges: ["cairn", "lamp"], closeness: 60, band: "almost", reasoning: nil)
      ]

      [parsed] = round_trip([page(attempts: [attempt(1, verdicts: verdicts)])])

      assert [attempt] = parsed.attempts
      assert attempt.bridges == [{"Melissa", "beacon"}, {"Jacob", "cairn"}]
      assert attempt.closeness == nil
      assert attempt.band == nil
      assert attempt.reasoning == nil
      assert attempt.quip == nil
    end
  end

  describe "a round trip of corrections" do
    test "reads a Page-level correction onto the Page, not onto the last Attempt" do
      page_correction = correction(note: "Truer to the night")

      attempt_correction =
        correction(
          attempt_number: 2,
          target: "bridge",
          original_value: "cairns",
          corrected_value: "cairn"
        )

      [parsed] =
        round_trip([
          page(
            attempts: [attempt(1), attempt(2, corrections: [attempt_correction])],
            corrections: [page_correction, attempt_correction]
          )
        ])

      assert [first, second] = parsed.attempts
      assert first.corrections == []

      assert second.corrections == [
               %{
                 author: "Jacob",
                 target: "bridge",
                 original: "cairns",
                 corrected: "cairn",
                 note: nil
               }
             ]

      assert parsed.corrections == [
               %{
                 author: "Jacob",
                 target: "recap",
                 original: "",
                 corrected: "We found the lighthouse.",
                 note: "Truer to the night"
               }
             ]
    end

    test "renders Page-level corrections as a sibling of the Attempts" do
      markdown = render([page(corrections: [correction([])])])

      assert markdown =~ "\n#### Corrections\n  - By Jacob: corrected recap to"
      refute markdown =~ "##### Corrections"
    end

    test "reads a Page with none as no corrections" do
      assert [%{corrections: []}] = round_trip([page()])
    end
  end

  describe "a round trip of what a Page and its Attempt read" do
    test "keeps the fields the parsed shape carries" do
      graded =
        verdict(
          closeness: 85,
          band: "meld",
          model: "gemini",
          prompt_version: "assay-2",
          latency_ms: 900,
          cost_usd: Decimal.new("0.001")
        )

      tap = %{reviewer_name: "Melissa", label: "too_harsh"}

      overrule = %{
        proposer_name: "Melissa",
        machine_closeness: 40,
        machine_reasoning: "Distinct ideas",
        couple_closeness: 85,
        couple_reasoning: "We both saw the shore"
      }

      view =
        page(
          melded: true,
          closed_because: "meld",
          closeness: 85,
          gives: [%{seat_name: "Melissa", text: "by the sea", mask: nil}],
          track: %{path: "/media/tracks/a.mp3", title: "Harbour Lights"},
          vamp: %Vamp{path: "/media/vamps/a.mp3"},
          experiment_id: "bait_against_plain",
          recap: %{recap: "They found the shore.", callback: "Again, the cairn."},
          attempts: [
            attempt(1,
              verdicts: [graded],
              carried: ["beacon", "cairn"],
              fairness_taps: [tap],
              overrules: [overrule]
            )
          ]
        )

      assert [parsed] = round_trip([view])

      assert parsed == %{
               bookends: ["lantern", "harbour"],
               melded: true,
               closeness: 85,
               give: "by the sea",
               gives: [%{seat_name: "Melissa", text: "by the sea"}],
               experiment: "Blinded (bait_against_plain)",
               arm: nil,
               track: "Harbour Lights",
               vamp: "the short piece",
               recap: %{recap: "They found the shore.", callback: "Again, the cairn."},
               corrections: [],
               attempts: [
                 %{
                   number: 1,
                   bookends: ["lantern", "harbour"],
                   bridges: [{"Melissa", "beacon"}, {"Jacob", "cairn"}],
                   closeness: 85,
                   band: "meld",
                   reasoning: "One went to sea, one stayed ashore.",
                   quip: "Ships passing in the fog.",
                   carried: ["beacon", "cairn"],
                   fairness_taps: [%{seat_name: "Melissa", label: "too_harsh"}],
                   overrule: %{
                     proposer: "Melissa",
                     original: 40,
                     overruled: 85,
                     reasoning: "We both saw the shore"
                   },
                   corrections: []
                 }
               ]
             }
    end
  end

  describe "parse/1 still reads an older export" do
    test "with legacy Anchors:, Status: and bare Track: and Vamp: lines" do
      legacy = """
      # The Chronicle

      ## Room: test-room

      ### Page 1: lantern · harbour
      - Status: Melded (meld)
      - Closeness: 80 / 100
      Track: Midnight Beacon
      Vamp: the short piece

      #### Attempt 1
      - Anchors: lantern · harbour
      - Bridges:
        - Melissa: cairn
        - Jacob: cairn
      - Closeness: 80 / 100 (meld)
      """

      assert {:ok, [page]} = Markdown.parse(legacy)
      assert page.melded
      assert page.track == "Midnight Beacon"
      assert page.vamp == "the short piece"
      assert [attempt] = page.attempts
      assert attempt.bookends == ["lantern", "harbour"]
      assert attempt.bridges == [{"Melissa", "cairn"}, {"Jacob", "cairn"}]
    end

    test "with no Track: line, as no Track" do
      legacy = """
      ### Page 1: lantern · harbour
      - Outcome: Melded (meld)

      #### Attempt 1
      - Bookends: lantern · harbour
      - Bridges:
        - Melissa: cairn
      - Closeness: 80 / 100 (meld)
      """

      assert {:ok, [page]} = Markdown.parse(legacy)
      assert page.track == nil
      assert page.vamp == nil
    end

    test "the Quips of priv/chronicles/dust.md" do
      assert {:ok, pages} = "priv/chronicles/dust.md" |> File.read!() |> Markdown.parse()

      quips = for page <- pages, attempt <- page.attempts, do: attempt.quip
      assert "Both players spotted lighthouse from miles away through the fog." in quips
      refute Enum.any?(quips, &(is_binary(&1) and String.starts_with?(&1, "-")))
    end
  end

  describe "render/3" do
    test "ends the document with the Spend line" do
      markdown = render([page()])
      assert String.ends_with?(markdown, "\n---\n\n" <> Spend.line(@spend) <> "\n")
    end

    test "writes No pages played yet. for an empty Chronicle" do
      assert render([]) ==
               "# The Chronicle\n\n## Room: dust\n\nNo pages played yet.\n\n---\n\n" <>
                 Spend.line(@spend) <> "\n"
    end

    test "writes a Track line and a Vamp line only when the Page kept them" do
      markdown =
        render([
          page(
            track: %{path: "/media/tracks/a.mp3", title: "Harbour Lights"},
            vamp: %Vamp{path: "/media/vamps/a.mp3"}
          ),
          page(bookends: ["desert", "oasis"], track: %{path: "/b.mp3", title: "Oasis"})
        ])

      assert markdown =~ "- Track: Harbour Lights\n- Vamp: the short piece"
      assert markdown =~ "- Track: Oasis"
      assert length(Regex.scan(~r/Vamp:/, markdown)) == 1
    end

    test "writes each Give's Mask" do
      mask = %Thereish.Mask{url: "/media/masks/mask-melissa.png", meta: %{}}
      markdown = render([page(gives: [%{seat_name: "Melissa", text: "cactus", mask: mask}])])

      assert markdown =~ "- Mask (Melissa): /media/masks/mask-melissa.png"
    end
  end
end
