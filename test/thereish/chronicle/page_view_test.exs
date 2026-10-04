defmodule Thereish.Chronicle.PageViewTest do
  @moduledoc """
  How a closed Page reads, projected from rows built in memory. No database and
  no Room: whether a Page is written down is the Chronicle's test; how it reads
  once it is, is this one.
  """
  use ExUnit.Case, async: true

  alias Thereish.Chronicle.Attempt
  alias Thereish.Chronicle.Bridge
  alias Thereish.Chronicle.Correction
  alias Thereish.Chronicle.FairnessTap
  alias Thereish.Chronicle.Give
  alias Thereish.Chronicle.Overrule
  alias Thereish.Chronicle.Page
  alias Thereish.Chronicle.PageView
  alias Thereish.Chronicle.Recap
  alias Thereish.Chronicle.Verdict
  alias Thereish.Mask
  alias Thereish.Rooms.Seat

  @room_id "room"
  @page_id "page"
  @mara "mara"
  @jacob "jacob"

  @no_rows %{
    overrules: [],
    corrections: [],
    fairness_taps: [],
    recaps: [],
    page_arms: %{assignments: [], outcomes: [], unblinded: MapSet.new()}
  }

  defp project(page, rows \\ %{}), do: PageView.project(page, Map.merge(@no_rows, rows))

  defp page(attrs) do
    struct!(
      %Page{
        id: @page_id,
        room_id: @room_id,
        document: %{"bookends" => ["lantern", "harbour"]},
        closed_because: "attempts_spent",
        melded: false,
        closeness: 27,
        opened_at: ~U[2026-10-03 20:00:00.000000Z],
        closed_at: ~U[2026-10-03 20:05:00.000000Z],
        gives: [],
        attempts: [attempt(1)],
        overrules: [],
        corrections: []
      },
      attrs
    )
  end

  defp attempt(number, attrs \\ []) do
    struct!(
      %Attempt{
        id: "attempt-#{number}",
        number: number,
        bookends: ["lantern", "harbour"],
        closeness: 27,
        melded: false,
        bridges: [bridge(@mara, "beacon", 0), bridge(@jacob, "cairn", 1)],
        verdicts: [verdict(furthest: ["beacon", "cairn"])]
      },
      attrs
    )
  end

  defp bridge(seat_id, word, position) do
    %Bridge{
      id: "bridge-#{word}-#{position}",
      seat_id: seat_id,
      seat: nil,
      bridge: word,
      position: position
    }
  end

  defp verdict(attrs) do
    struct!(
      %Verdict{id: "verdict", graded: true, closeness: 27, band: "miss", position: 0},
      attrs
    )
  end

  defp overrule(attrs) do
    struct!(
      %Overrule{
        id: "overrule",
        room_id: @room_id,
        page_id: @page_id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"],
        proposer: nil,
        machine_closeness: 27,
        couple_closeness: 85,
        couple_reasoning: "We both saw the shore."
      },
      attrs
    )
  end

  defp tap(attrs) do
    struct!(
      %FairnessTap{
        id: "tap",
        room_id: @room_id,
        page_id: @page_id,
        attempt_number: 1,
        bookends: ["lantern", "harbour"],
        bridges: ["beacon", "cairn"],
        closeness: 27,
        label: "too_harsh",
        seat_id: @mara,
        seat: %Seat{name: "Mara"}
      },
      attrs
    )
  end

  defp correction(attrs) do
    struct!(
      %Correction{
        id: "correction",
        room_id: @room_id,
        page_id: @page_id,
        seat_id: @jacob,
        seat: %Seat{name: "Jacob"},
        inserted_at: ~U[2026-10-03 21:00:00.000000Z]
      },
      attrs
    )
  end

  defp recap(id, text, attrs \\ []) do
    struct!(
      %Recap{
        id: id,
        room_id: @room_id,
        page_id: @page_id,
        recap: text,
        callback: nil,
        inserted_at: ~U[2026-10-03 20:10:00.000000Z]
      },
      attrs
    )
  end

  defp mask(name), do: %Mask{url: "/media/masks/#{name}.png", meta: %{}}

  describe "project/2 reads the Page" do
    test "into a %PageView{} carrying its document, outcome and blinded Experiment" do
      view = project(page([]))

      assert %PageView{} = view
      assert view.id == @page_id
      assert view.room_id == @room_id
      assert view.bookends == ["lantern", "harbour"]
      assert view.closed_because == "attempts_spent"
      assert view.full_table == nil
      assert view.recap == nil
      assert view.experiment_unblinded == false
      assert view.arm == nil
      assert view.trap_converged == nil
      assert view.deep_converged == nil
    end

    test "with no gives as a Page with no gives" do
      view = project(page(gives: []))

      assert view.gives == []
      assert view.give == nil
    end

    test "with each Give under the Mask its Seat wore" do
      view =
        project(
          page(
            gives: [%Give{id: "give", seat_id: @mara, seat: nil, text: "cactus", order: 0}],
            masks_meta: %{@mara => mask("mara")}
          )
        )

      assert [give] = view.gives
      assert give.seat_name == "Seat"
      assert give.text == "cactus"
      assert give.mask == mask("mara")
    end
  end

  describe "project/2 carries Bookends forward" do
    test "after a miss at a Full table, as every Bridge" do
      view =
        project(
          page(
            document: %{"bookends" => ["lantern", "harbour"], "full_table" => true},
            attempts: [
              attempt(1,
                bridges: [
                  bridge(@mara, "beacon", 0),
                  bridge(@jacob, "cairn", 1),
                  bridge("ada", "lamp", 2)
                ]
              )
            ]
          )
        )

      assert view.full_table == true
      assert [%{carried: ["beacon", "cairn", "lamp"]}] = view.attempts
    end

    test "after a miss away from a Full table, as the furthest pair" do
      view =
        project(
          page(
            document: %{"bookends" => ["lantern", "harbour"], "full_table" => false},
            attempts: [
              attempt(1,
                bridges: [
                  bridge(@mara, "beacon", 0),
                  bridge(@jacob, "cairn", 1),
                  bridge("ada", "lamp", 2),
                  bridge("sam", "seagull", 3)
                ],
                verdicts: [verdict(furthest: ["beacon", "seagull"])]
              )
            ]
          )
        )

      assert [%{carried: ["beacon", "seagull"]}] = view.attempts
    end

    test "from a Page written before the rule, as the furthest pair" do
      view =
        project(page(attempts: [attempt(1, verdicts: [verdict(furthest: ["beacon", "cairn"])])]))

      assert view.full_table == nil
      assert [%{carried: ["beacon", "cairn"]}] = view.attempts
    end

    test "as the next Attempt's Bookends when there was one" do
      view =
        project(
          page(
            document: %{"bookends" => ["lantern", "harbour"], "full_table" => true},
            attempts: [attempt(1), attempt(2, bookends: ["beacon", "cairn"])]
          )
        )

      assert [%{carried: ["beacon", "cairn"]}, %{carried: ["beacon", "cairn"]}] = view.attempts
    end

    test "as nothing after a Meld" do
      view = project(page(melded: true, attempts: [attempt(1, melded: true)]))

      assert [%{carried: nil}] = view.attempts
    end

    test "as the first two Bridges when the Attempt could not be graded" do
      view =
        project(
          page(
            document: %{"bookends" => ["lantern", "harbour"], "full_table" => false},
            attempts: [
              attempt(1,
                bridges: [
                  bridge(@mara, "beacon", 0),
                  bridge(@jacob, "cairn", 1),
                  bridge("ada", "lamp", 2)
                ],
                verdicts: [verdict(graded: false, closeness: nil, band: nil, furthest: nil)]
              )
            ]
          )
        )

      assert [%{carried: ["beacon", "cairn"]}] = view.attempts
    end
  end

  describe "project/2 dresses Bookends as chips" do
    test "on the first Attempt, from the Gives that dealt them, wearing no Mask" do
      origins = [
        %{
          "word" => "lantern",
          "give" => "setting one",
          "seat_id" => @mara,
          "seat_name" => "Mara"
        },
        %{
          "word" => "harbour",
          "give" => "setting two",
          "seat_id" => @jacob,
          "seat_name" => "Jacob"
        }
      ]

      view =
        project(
          page(
            document: %{"bookends" => ["lantern", "harbour"], "bookend_origins" => origins},
            masks_meta: %{@mara => mask("mara"), @jacob => mask("jacob")}
          )
        )

      assert Enum.map(view.bookend_origins, & &1.give) == ["setting one", "setting two"]

      # Today's behaviour, kept on purpose: the chip names its Seat and still
      # wears no Mask.
      assert [%{bookend_chips: chips}] = view.attempts

      assert chips == [
               %{
                 word: "lantern",
                 give: "setting one",
                 seat_id: @mara,
                 seat_name: "Mara",
                 mask: nil
               },
               %{
                 word: "harbour",
                 give: "setting two",
                 seat_id: @jacob,
                 seat_name: "Jacob",
                 mask: nil
               }
             ]
    end

    test "on the first Attempt with no origins, as bare words" do
      view = project(page([]))

      assert [%{bookend_chips: [%{word: "lantern", mask: nil}, %{word: "harbour", mask: nil}]}] =
               view.attempts
    end

    test "on a later Attempt, each claiming the Mask of the Seat whose Bridge it carried" do
      view =
        project(
          page(
            masks_meta: %{@mara => mask("mara"), @jacob => mask("jacob")},
            attempts: [
              attempt(1, bridges: [bridge(@mara, "stone", 0), bridge(@jacob, "stone", 1)]),
              attempt(2, bookends: ["stone", "stone", "moss"])
            ]
          )
        )

      assert [_first, %{bookend_chips: chips}] = view.attempts

      assert chips == [
               %{word: "stone", seat_id: @mara, mask: mask("mara")},
               %{word: "stone", seat_id: @jacob, mask: mask("jacob")},
               %{word: "moss", mask: nil}
             ]
    end
  end

  describe "project/2 gathers overrules and taps" do
    test "matched by Page id, whatever their Bookends say" do
      row_attrs = [bookends: ["something", "else"]]
      other_page = [page_id: "another-page", bookends: ["something", "else"]]

      view =
        project(page([]), %{
          overrules: [overrule(row_attrs), overrule([id: "elsewhere"] ++ other_page)],
          fairness_taps: [tap(row_attrs), tap([id: "elsewhere"] ++ other_page)]
        })

      assert [%{id: "overrule", proposer_name: "Player"}] = view.overrules
      assert [%{id: "tap", reviewer_name: "Mara", source: "participant"}] = view.fairness_taps

      assert [attempt] = view.attempts
      assert [%{id: "overrule"}] = attempt.overrules
      assert [%{id: "tap"}] = attempt.fairness_taps
      assert [%{overruled: true}] = attempt.verdicts
    end

    test "from before rows named their Page, matched by Room and Bookends" do
      legacy = [page_id: nil]

      view =
        project(page([]), %{
          overrules: [
            overrule(legacy),
            overrule([id: "other-room", room_id: "elsewhere"] ++ legacy),
            overrule([id: "other-bookends", bookends: ["moss", "stone"]] ++ legacy)
          ],
          fairness_taps: [
            tap(legacy),
            tap([id: "other-attempt", attempt_number: 2] ++ legacy)
          ]
        })

      assert [%{id: "overrule"}] = view.overrules
      assert [%{id: "tap"}] = view.fairness_taps
      assert [%{overrules: [%{id: "overrule"}], fairness_taps: [%{id: "tap"}]}] = view.attempts
    end

    test "and leaves a Verdict nobody overruled as it was" do
      view = project(page([]))

      assert [%{overrules: [], fairness_taps: [], verdicts: [%{overruled: false}]}] =
               view.attempts
    end
  end

  describe "project/2 reads corrections over what was written" do
    test "a corrected Bridge reads as corrected, with the original underneath" do
      view =
        project(page([]), %{
          corrections: [
            correction(
              attempt_number: 1,
              target: "bridge",
              original_value: "cairn",
              corrected_value: "cairns",
              note: "Phone autocorrect"
            )
          ]
        })

      assert [%{bridges: [beacon, cairn], corrections: [attempt_correction]}] = view.attempts
      assert beacon.corrected? == false
      assert beacon.original_bridge == nil
      assert cairn.bridge == "cairns"
      assert cairn.original_bridge == "cairn"
      assert cairn.corrected? == true
      assert attempt_correction.author_name == "Jacob"
      assert [%{corrected_value: "cairns", author_name: "Jacob"}] = view.corrections
    end
  end

  describe "project/2 reads the recap" do
    test "as the later of two the Scribe wrote" do
      view =
        project(page([]), %{
          recaps: [
            recap("first", "An earlier draft."),
            recap("second", "A trek to the shore.", callback: "The lantern again.")
          ]
        })

      assert view.recap.id == "second"
      assert view.recap.recap == "A trek to the shore."
      assert view.recap.callback == "The lantern again."
      assert view.recap.corrected? == false
      assert view.recap.original_recap == nil
    end

    test "ignoring recaps of other Pages" do
      view = project(page([]), %{recaps: [recap("other", "Elsewhere.", page_id: "another-page")]})

      assert view.recap == nil
    end

    test "with the players' correction over the Scribe's" do
      view =
        project(page([]), %{
          recaps: [recap("written", "The Scribe's words.", callback: "A callback.")],
          corrections: [correction(target: "recap", corrected_value: "Our words.")]
        })

      assert view.recap.id == "written"
      assert view.recap.recap == "Our words."
      assert view.recap.original_recap == "The Scribe's words."
      assert view.recap.corrected? == true
      assert view.recap.callback == "A callback."
    end

    test "as the players' correction alone when the Scribe wrote nothing" do
      view =
        project(page([]), %{corrections: [correction(target: "recap", corrected_value: "Ours.")]})

      assert view.recap == %{
               id: "correction",
               recap: "Ours.",
               original_recap: nil,
               corrected?: true,
               callback: nil,
               model: nil,
               prompt_version: nil,
               cost_usd: nil,
               latency_ms: nil,
               attempts: nil,
               inserted_at: ~U[2026-10-03 21:00:00.000000Z]
             }
    end
  end

  describe "about_attempt?/3" do
    setup do
      page = page(attempts: [attempt(1), attempt(2, bookends: ["beacon", "cairn"])])
      [first, second] = page.attempts
      %{page: page, first: first, second: second}
    end

    test "holds for a row naming the Page and the Attempt's number", ctx do
      row = overrule(bookends: ["anything", "at all"])

      assert PageView.about_attempt?(row, ctx.page, ctx.first)
      refute PageView.about_attempt?(row, ctx.page, ctx.second)
    end

    test "holds for a row from before rows named their Page, by Room and Bookends", ctx do
      row = tap(page_id: nil, attempt_number: 2, bookends: ["beacon", "cairn"])

      assert PageView.about_attempt?(row, ctx.page, ctx.second)
      refute PageView.about_attempt?(%{row | room_id: "elsewhere"}, ctx.page, ctx.second)
      refute PageView.about_attempt?(%{row | bookends: ["moss"]}, ctx.page, ctx.second)
      refute PageView.about_attempt?(row, ctx.page, ctx.first)
    end

    test "does not hold for a row naming another Page with other Bookends", ctx do
      row = overrule(page_id: "another-page", bookends: ["moss", "stone"])

      refute PageView.about_attempt?(row, ctx.page, ctx.first)
    end
  end
end
